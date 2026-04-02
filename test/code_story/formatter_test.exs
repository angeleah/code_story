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

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
