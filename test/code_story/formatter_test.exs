defmodule CodeStory.FormatterTest do
  use ExUnit.Case, async: true

  alias CodeStory.Formatter

  @simple_tree [
    %{
      module: MyApp,
      function: :add,
      args: [num1: 3, num2: 2],
      return: 5,
      children: []
    }
  ]

  @nested_tree [
    %{
      module: MyApp,
      function: :add_sub_mult,
      args: [num1: 3, num2: 2],
      return: 20,
      children: [
        %{module: MyApp, function: :add, args: [num1: 3, num2: 2], return: 5, children: []},
        %{module: MyApp, function: :subtract, args: [num1: 5, num2: 1], return: 4, children: []},
        %{module: MyApp, function: :mult, args: [num1: 4, num2: 5], return: 20, children: []}
      ]
    }
  ]

  # A 4-level chain A→B→C→D (single child each) for depth-cap assertions.
  @deep_tree [
    %{
      module: MyApp,
      function: :a,
      args: [x: 1],
      return: :ra,
      children: [
        %{
          module: MyApp,
          function: :b,
          args: [x: 2],
          return: :rb,
          children: [
            %{
              module: MyApp,
              function: :c,
              args: [x: 3],
              return: :rc,
              children: [
                %{module: MyApp, function: :d, args: [x: 4], return: :rd, children: []}
              ]
            }
          ]
        }
      ]
    }
  ]

  describe "format/2 show_args: true" do
    test "formats a simple leaf call with module and function name" do
      output = Formatter.format(@simple_tree, show_args: true)
      plain = strip_ansi(output)
      lines = String.split(plain, "\n")

      assert Enum.at(lines, 0) == "--- CodeStory Trace ---"
      assert Enum.at(lines, 1) == "MyApp.add"
      assert Enum.at(lines, 2) == "  num1: 3"
      assert Enum.at(lines, 3) == "  num2: 2"
      assert Enum.at(lines, 4) == "=> 5"
      assert Enum.at(lines, 5) == "--- End Trace ---"
    end

    test "formats nested calls with module names and blank line separators" do
      output = Formatter.format(@nested_tree, show_args: true)
      plain = strip_ansi(output)

      # Children at same indent as args (2 spaces), with module prefix
      assert plain =~ "  num2: 2\n\n  MyApp.add\n"
      # Blank line before return, return at function's level with module prefix
      assert plain =~ "  => 20\n\n=> MyApp.add_sub_mult returned 20"
    end
  end

  describe "format/2 non-show_args: true" do
    test "shows values only without names" do
      output = Formatter.format(@simple_tree, show_args: false)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add\n"
      assert plain =~ "  3\n"
      assert plain =~ "  2\n"
      refute plain =~ "num1:"
    end

    test "nested show_args: false" do
      output = Formatter.format(@nested_tree, show_args: false)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add_sub_mult\n"
      assert plain =~ "  MyApp.add\n"
      assert plain =~ "  => 5"
    end
  end

  describe "format/2 with ANSI colors" do
    test "includes ANSI color codes" do
      output = Formatter.format(@simple_tree, show_args: true)

      assert output =~ "\e["
    end
  end

  describe "format/2 interrupted nodes" do
    test "renders nil return as => ?" do
      tree = [
        %{module: MyApp, function: :long_running, args: [x: 1], return: nil, children: []}
      ]

      output = Formatter.format(tree, show_args: true)
      plain = strip_ansi(output)

      assert plain =~ "=> ?"
    end
  end

  describe "format_plain/2" do
    test "strips all ANSI codes" do
      output = Formatter.format_plain(@simple_tree, show_args: true)

      refute output =~ "\e["
      assert output =~ "--- CodeStory Trace ---"
      assert output =~ "MyApp.add"
    end
  end

  describe "format/2 truncates large values" do
    test "truncates structs to show limited fields" do
      big_struct = %{
        __struct__: MyApp.User,
        name: "Alice",
        email: "a@b.com",
        age: 30,
        address: "123 Main St",
        phone: "555-1234",
        role: :admin
      }

      tree = [
        %{
          module: MyApp,
          function: :process,
          args: [user: big_struct],
          return: :ok,
          children: []
        }
      ]

      output = Formatter.format(tree, show_args: true)
      plain = strip_ansi(output)

      assert plain =~ "..."
      refute plain =~ "phone"
    end

    test "truncates large maps to show limited keys" do
      big_map = %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5, "f" => 6, "g" => 7}

      tree = [
        %{
          module: MyApp,
          function: :process,
          args: [data: big_map],
          return: big_map,
          children: []
        }
      ]

      output = Formatter.format(tree, show_args: true)
      plain = strip_ansi(output)

      assert plain =~ "..."
    end
  end

  describe "format/2 detail: :novel shows complete values" do
    test "does not truncate structs" do
      big_struct = %{
        __struct__: MyApp.User,
        name: "Alice",
        email: "a@b.com",
        age: 30,
        address: "123 Main St",
        phone: "555-1234",
        role: :admin
      }

      tree = [
        %{
          module: MyApp,
          function: :process,
          args: [user: big_struct],
          return: :ok,
          children: []
        }
      ]

      output = Formatter.format(tree, show_args: true, detail: :novel)
      plain = strip_ansi(output)

      # Should show all fields including phone
      assert plain =~ "phone"
      assert plain =~ "address"
      assert plain =~ "role"
    end

    test "does not truncate large maps" do
      big_map = %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5, "f" => 6, "g" => 7}

      tree = [
        %{
          module: MyApp,
          function: :process,
          args: [data: big_map],
          return: big_map,
          children: []
        }
      ]

      output = Formatter.format(tree, show_args: true, detail: :novel)
      plain = strip_ansi(output)

      # Should show all keys
      assert plain =~ "\"g\" => 7"
      refute plain =~ "..."
    end
  end

  describe "format/2 detail: :outline shows only function names and arg names" do
    test "simple leaf shows function and arg names without values or return" do
      output = Formatter.format(@simple_tree, detail: :outline)
      plain = strip_ansi(output)
      lines = String.split(plain, "\n")

      assert Enum.at(lines, 0) == "--- CodeStory Trace ---"
      assert Enum.at(lines, 1) == "MyApp.add"
      assert Enum.at(lines, 2) == "  num1"
      assert Enum.at(lines, 3) == "  num2"
      assert Enum.at(lines, 4) == "--- End Trace ---"
      refute plain =~ "=>"
      refute plain =~ ": 3"
      refute plain =~ ": 2"
    end

    test "nested calls show structure without values or returns" do
      output = Formatter.format(@nested_tree, detail: :outline)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add_sub_mult"
      assert plain =~ "  MyApp.add"
      assert plain =~ "  MyApp.subtract"
      assert plain =~ "  MyApp.mult"
      refute plain =~ "=> "
      refute plain =~ "returned"
    end
  end

  describe "format/2 with folded nodes (count / varies)" do
    test "a node with count renders ×N on the function line" do
      tree = [
        %{
          module: MyApp,
          function: :add,
          args: [num1: 3, num2: 2],
          return: 5,
          children: [],
          count: 98
        }
      ]

      plain = strip_ansi(Formatter.format(tree, show_args: true))
      lines = String.split(plain, "\n")
      assert Enum.at(lines, 1) == "MyApp.add ×98"
    end

    test "a varies node renders ×N (varies)" do
      tree = [
        %{
          module: MyApp,
          function: :add,
          args: [num1: 3, num2: 2],
          return: 5,
          children: [],
          count: 98,
          varies: true
        }
      ]

      plain = strip_ansi(Formatter.format(tree, show_args: true))
      lines = String.split(plain, "\n")
      assert Enum.at(lines, 1) == "MyApp.add ×98 (varies)"
    end

    test "a node without count renders exactly as before (regression)" do
      plain = strip_ansi(Formatter.format(@simple_tree, show_args: true))
      refute plain =~ "×"
    end

    test "×N appears on the function line only, never on the return line" do
      tree = [
        %{
          module: MyApp,
          function: :add_sub_mult,
          args: [num1: 3, num2: 2],
          return: 20,
          count: 98,
          children: [%{module: MyApp, function: :add, args: [], return: 5, children: []}]
        }
      ]

      plain = strip_ansi(Formatter.format(tree, show_args: true))
      assert length(Regex.scan(~r/×98/, plain)) == 1
      assert plain =~ "=> MyApp.add_sub_mult returned 20"
    end

    test "×N is stripped by format_plain" do
      tree = [%{module: MyApp, function: :add, args: [], return: 5, children: [], count: 98}]
      out = Formatter.format_plain(tree, show_args: true)
      refute out =~ "\e["
      assert out =~ "MyApp.add ×98"
    end

    test ":outline detail also renders ×N on the function line" do
      tree = [
        %{
          module: MyApp,
          function: :add,
          args: [num1: 3, num2: 2],
          return: 5,
          children: [],
          count: 98
        }
      ]

      plain = strip_ansi(Formatter.format(tree, detail: :outline))
      lines = String.split(plain, "\n")
      assert Enum.at(lines, 1) == "MyApp.add ×98"
    end
  end

  describe "format/2 with :depth" do
    test "depth: :infinity (and omitted) renders unchanged; no marker" do
      base = strip_ansi(Formatter.format(@nested_tree, show_args: true))
      inf = strip_ansi(Formatter.format(@nested_tree, show_args: true, depth: :infinity))
      assert inf == base
      refute base =~ "more level"
    end

    test "depth: 1 shows only the root with a marker; child names absent" do
      plain = strip_ansi(Formatter.format(@nested_tree, show_args: true, depth: 1))
      assert plain =~ "MyApp.add_sub_mult"
      assert plain =~ "num1: 3"
      assert plain =~ "=> MyApp.add_sub_mult returned 20"
      assert plain =~ "more level"
      refute plain =~ "MyApp.subtract"
      refute plain =~ "MyApp.mult"
    end

    test "depth caps at N levels with correct K in the marker" do
      d1 = strip_ansi(Formatter.format(@deep_tree, show_args: true, depth: 1))
      assert d1 =~ "MyApp.a"
      assert d1 =~ "… (3 more levels)"
      refute d1 =~ "MyApp.b"
      refute d1 =~ "MyApp.c"
      refute d1 =~ "MyApp.d"

      d2 = strip_ansi(Formatter.format(@deep_tree, show_args: true, depth: 2))
      assert d2 =~ "MyApp.a"
      assert d2 =~ "MyApp.b"
      assert d2 =~ "… (2 more levels)"
      refute d2 =~ "MyApp.c"
      refute d2 =~ "MyApp.d"
    end

    test "a leaf at the cap renders normally with no marker" do
      capped = strip_ansi(Formatter.format(@simple_tree, show_args: true, depth: 1))
      full = strip_ansi(Formatter.format(@simple_tree, show_args: true, depth: :infinity))
      assert capped == full
      refute capped =~ "more level"
    end

    test "format_plain shows the plain marker and no ANSI" do
      out = Formatter.format_plain(@deep_tree, show_args: true, depth: 1)
      refute out =~ "\e["
      assert out =~ "… (3 more levels)"
    end

    test ":outline detail also truncates with a marker" do
      plain = strip_ansi(Formatter.format(@deep_tree, detail: :outline, depth: 1))
      assert plain =~ "MyApp.a"
      assert plain =~ "… (3 more levels)"
      refute plain =~ "MyApp.b"
    end

    test "a truncated node still shows its own return line" do
      plain = strip_ansi(Formatter.format(@deep_tree, show_args: true, depth: 1))
      assert plain =~ "=> MyApp.a returned :ra"
    end

    test "truncation composes with a folded (count) node" do
      folded = [
        %{
          module: MyApp,
          function: :deliver,
          args: [id: 1],
          return: :ok,
          count: 5,
          varies: true,
          children: [
            %{
              module: MyApp,
              function: :inner,
              args: [],
              return: :x,
              children: [
                %{module: MyApp, function: :deep, args: [], return: :y, children: []}
              ]
            }
          ]
        }
      ]

      plain = strip_ansi(Formatter.format(folded, show_args: true, depth: 1))
      assert plain =~ "MyApp.deliver ×5 (varies)"
      assert plain =~ "id: 1"
      assert plain =~ "more level"
      assert plain =~ "=> MyApp.deliver returned :ok"
      refute plain =~ "MyApp.inner"
    end

    test "depth >= tree height renders the full tree with no marker" do
      for n <- [4, 99] do
        plain = strip_ansi(Formatter.format(@deep_tree, show_args: true, depth: n))
        assert plain =~ "MyApp.d"
        refute plain =~ "more level"
      end
    end

    test "K == 1 renders singular 'more level'" do
      plain = strip_ansi(Formatter.format(@deep_tree, show_args: true, depth: 3))
      assert plain =~ "… (1 more level)"
      refute plain =~ "1 more levels"
      assert plain =~ "MyApp.c"
      refute plain =~ "MyApp.d"
    end

    test "depth: 0 is clamped to depth: 1" do
      assert Formatter.format(@deep_tree, show_args: true, depth: 0) ==
               Formatter.format(@deep_tree, show_args: true, depth: 1)
    end

    test "a float depth is truncated to an integer cap (2.0 behaves as 2)" do
      assert Formatter.format(@deep_tree, show_args: true, depth: 2.0) ==
               Formatter.format(@deep_tree, show_args: true, depth: 2)
    end

    test ":novel detail also truncates" do
      plain = strip_ansi(Formatter.format(@deep_tree, show_args: true, detail: :novel, depth: 1))
      assert plain =~ "MyApp.a"
      assert plain =~ "more level"
      refute plain =~ "MyApp.b"
    end
  end

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
