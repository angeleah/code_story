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
    test "formats a simple leaf call as an inline signature" do
      output = Formatter.format(@simple_tree, show_args: true)
      plain = strip_ansi(output)
      lines = String.split(plain, "\n")

      assert Enum.at(lines, 0) == "--- CodeStory Trace ---"
      assert Enum.at(lines, 1) == "MyApp.add(num1: 3, num2: 2) => 5"
      assert Enum.at(lines, 2) == "--- End Trace ---"
    end

    test "formats nested calls: inline parent signature, inline children, bottom return" do
      output = Formatter.format(@nested_tree, show_args: true)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add_sub_mult(num1: 3, num2: 2)\n"
      # children are inline leaves, indented under the signature
      assert plain =~ "  MyApp.add(num1: 3, num2: 2) => 5\n"
      assert plain =~ "  MyApp.mult(num1: 4, num2: 5) => 20\n"
      # non-leaf return still on its own bottom line
      assert plain =~ "=> MyApp.add_sub_mult returned 20"
    end
  end

  describe "format/2 non-show_args: true" do
    test "shows values only without names (inline positional)" do
      output = Formatter.format(@simple_tree, show_args: false)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add(3, 2) => 5"
      refute plain =~ "num1:"
    end

    test "nested show_args: false (inline positional)" do
      output = Formatter.format(@nested_tree, show_args: false)
      plain = strip_ansi(output)

      assert plain =~ "MyApp.add_sub_mult(3, 2)\n"
      assert plain =~ "  MyApp.add(3, 2) => 5\n"
    end
  end

  describe "format/2 with ANSI colors" do
    test "includes ANSI color codes" do
      output = Formatter.format(@simple_tree, show_args: true)

      assert output =~ "\e["
    end

    test "semantic colors are bold for dual-background legibility (no bare codes)" do
      output = Formatter.format(@simple_tree, show_args: true)

      # function name = bold blue, return = bold green, header = bold cyan
      assert output =~ "\e[1;34m"
      assert output =~ "\e[1;32m"
      assert output =~ "\e[1;36m"
      # and none of the non-bold forms remain
      refute output =~ "\e[34m"
      refute output =~ "\e[32m"
      refute output =~ "\e[36m"
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
    test "simple leaf shows an inline names-only signature, no values or return" do
      output = Formatter.format(@simple_tree, detail: :outline)
      plain = strip_ansi(output)
      lines = String.split(plain, "\n")

      assert Enum.at(lines, 0) == "--- CodeStory Trace ---"
      assert Enum.at(lines, 1) == "MyApp.add(num1, num2)"
      assert Enum.at(lines, 2) == "--- End Trace ---"
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
      assert Enum.at(lines, 1) == "MyApp.add(num1: 3, num2: 2) => 5 ×98"
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
      assert Enum.at(lines, 1) == "MyApp.add(num1: 3, num2: 2) => 5 ×98 (varies)"
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
      assert out =~ "MyApp.add() => 5 ×98"
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
      assert Enum.at(lines, 1) == "MyApp.add(num1, num2) ×98"
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
      assert plain =~ "MyApp.deliver(id: 1) ×5 (varies)"
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

  describe "boundary signatures" do
    defp boundary(fun, args, ret, extra \\ %{}) do
      Map.merge(
        %{
          module: MyApp.Repo,
          function: fun,
          args: args,
          return: ret,
          children: [],
          boundary: true
        },
        extra
      )
    end

    test "renders an inline signature (values, not positional names) in one line" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok)
      plain = strip_ansi(Formatter.format([node], show_args: true))
      lines = String.split(plain, "\n")

      assert Enum.at(lines, 1) == "MyApp.Repo.get!(queryable: MyApp.User, id: 1) => :ok"
      refute plain =~ "arg1"
      refute plain =~ "arg2"
    end

    test ":outline shows known names only — no values, no return" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok)
      plain = strip_ansi(Formatter.format([node], detail: :outline))
      assert plain =~ "MyApp.Repo.get!(queryable, id)"
      refute plain =~ "MyApp.User"
      refute plain =~ "=>"
    end

    test ":outline write call shows `changeset`; preload shows `struct, preloads`" do
      insert = boundary(:insert!, [arg1: %{__struct__: MyApp.Log, id: 1}], :ok)
      pre = boundary(:preload, [arg1: %{__struct__: MyApp.Order, id: 9}, arg2: [:event]], :ok)

      assert strip_ansi(Formatter.format([insert], detail: :outline)) =~
               "MyApp.Repo.insert!(changeset)"

      assert strip_ansi(Formatter.format([pre], detail: :outline)) =~
               "MyApp.Repo.preload(struct, preloads)"
    end

    test ":outline folded boundary: `Mod.fun(values) ×N` — one space, no =>" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok, %{count: 2, varies: true})
      plain = strip_ansi(Formatter.format([node], detail: :outline))
      assert plain =~ "MyApp.Repo.get!(queryable, id) ×2 (varies)"
      refute plain =~ "=>"
    end

    test ":outline boundary with children: signature (no return) then children" do
      child = %{
        module: MyApp.CustomType,
        function: :load,
        args: [raw: "x"],
        return: :ok,
        children: []
      }

      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], %{id: 1}, %{children: [child]})
      lines = String.split(strip_ansi(Formatter.format([node], detail: :outline)), "\n")

      assert Enum.at(lines, 1) == "MyApp.Repo.get!(queryable, id)"
      assert Enum.any?(lines, &(&1 =~ "MyApp.CustomType.load"))
      refute Enum.any?(lines, &(&1 =~ "=>"))
    end

    test ":outline boundary nested under a user fn also drops the return" do
      b = boundary(:all, [q: [1, 2], s: "x"], :ok)
      parent = %{module: MyApp, function: :load, args: [x: 1], return: :ok, children: [b]}
      plain = strip_ansi(Formatter.format([parent], detail: :outline))

      assert plain =~ "MyApp.Repo.all("
      refute plain =~ "=>"
    end

    test ":short_story and :novel keep the boundary return (unchanged)" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok)

      assert strip_ansi(Formatter.format([node], detail: :short_story)) =~
               "MyApp.Repo.get!(queryable: MyApp.User, id: 1) => :ok"

      assert strip_ansi(Formatter.format([node], detail: :novel)) =~
               "MyApp.Repo.get!(queryable: MyApp.User, id: 1) => :ok"
    end

    test "values use compact opts even when the boundary is nested in :outline" do
      # A boundary reached as a CHILD in :outline: the outline clause recurses with
      # []; the boundary clause must re-derive compact opts, not fall to Elixir
      # defaults (limit: 50 / printable_limit: 4096).
      big_list = Enum.to_list(1..10)
      long_str = String.duplicate("z", 80)
      b = boundary(:all, [q: big_list, s: long_str], :ok)
      parent = %{module: MyApp, function: :load, args: [x: 1], return: :ok, children: [b]}

      short = strip_ansi(Formatter.format([parent], detail: :short_story))
      novel = strip_ansi(Formatter.format([parent], detail: :novel))

      # :short_story applies compact opts to the boundary's values → truncation marker
      assert short =~ "..."
      # :novel shows the full list + string → no truncation marker anywhere
      refute novel =~ "..."
      # :outline is names-only (no values) → nothing to truncate
      refute strip_ansi(Formatter.format([parent], detail: :outline)) =~ "..."
    end

    test "a folded boundary renders the signature plus ×N (varies) after the return" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok, %{count: 2, varies: true})
      plain = strip_ansi(Formatter.format([node], show_args: true))
      assert plain =~ "MyApp.Repo.get!(queryable: MyApp.User, id: 1) => :ok ×2 (varies)"
    end

    test "a boundary with a nil return renders => ?" do
      node = boundary(:insert!, [arg1: :x], nil)
      plain = strip_ansi(Formatter.format([node], show_args: true))
      assert plain =~ "MyApp.Repo.insert!(changeset: :x) => ?"
    end

    test "a boundary with no args renders Mod.fun()" do
      node = boundary(:reset, [], :ok)
      plain = strip_ansi(Formatter.format([node], show_args: true))
      assert plain =~ "MyApp.Repo.reset() => :ok"
    end

    test "format_plain strips ANSI from a boundary signature" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok)
      out = Formatter.format_plain([node], show_args: true)
      refute out =~ "\e["
      assert out =~ "MyApp.Repo.get!(queryable: MyApp.User, id: 1) => :ok"
    end

    test "a boundary WITH children renders the signature then its children (no silent drop)" do
      child = %{
        module: MyApp.CustomType,
        function: :load,
        args: [raw: "x"],
        return: :ok,
        children: []
      }

      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], %{id: 1}, %{children: [child]})

      plain = strip_ansi(Formatter.format([node], show_args: true))
      assert plain =~ "MyApp.Repo.get!(queryable: MyApp.User, id: 1) =>"
      # the cross-module child is rendered, not silently dropped
      assert plain =~ "MyApp.CustomType.load"
      assert plain =~ "raw: \"x\""
    end

    test "non-boundary nodes are unchanged (no signature form)" do
      node = %{module: MyApp, function: :add, args: [num1: 3, num2: 2], return: 5, children: []}
      plain = strip_ansi(Formatter.format([node], detail: :outline))
      # outline: name-only, no values, no return, no inline "(...) =>"
      refute plain =~ "=>"
      refute plain =~ "(3, 2)"
    end

    test ":short_story get_by! → queryable + filters" do
      node = boundary(:get_by!, [arg1: MyApp.Settings, arg2: [event_id: 1]], :ok)
      plain = strip_ansi(Formatter.format([node], show_args: true))

      assert plain =~
               "MyApp.Repo.get_by!(queryable: MyApp.Settings, filters: [event_id: 1]) => :ok"
    end

    test "composes with #Ecto.Query<Schema> compaction on the queryable value" do
      query = %{__struct__: Ecto.Query, from: %{source: {"regs", MyApp.Reg}}}
      node = boundary(:all, [arg1: query], [])
      plain = strip_ansi(Formatter.format([node], show_args: true))
      assert plain =~ "MyApp.Repo.all(queryable: #Ecto.Query<MyApp.Reg>) => []"
    end

    test "unmapped function falls back to positional values (short_story + outline)" do
      node = boundary(:insert_all, [arg1: MyApp.User, arg2: :entries], 5)
      short = strip_ansi(Formatter.format([node], show_args: true))
      outline = strip_ansi(Formatter.format([node], detail: :outline))

      assert short =~ "MyApp.Repo.insert_all(MyApp.User, :entries) => 5"
      refute short =~ "queryable"
      assert outline =~ "MyApp.Repo.insert_all(MyApp.User, :entries)"
      refute outline =~ "=>"
    end

    test "aggregate renders with its Ecto param names across the dial" do
      node = boundary(:aggregate, [arg1: MyApp.User, arg2: :count], 5)
      short = strip_ansi(Formatter.format([node], show_args: true))
      outline = strip_ansi(Formatter.format([node], detail: :outline))

      assert short =~ "MyApp.Repo.aggregate(queryable: MyApp.User, aggregate: :count) => 5"
      assert outline =~ "MyApp.Repo.aggregate(queryable, aggregate)"
      refute outline =~ "=>"
    end

    test "surplus arg past the known-name list pads to a bare value, never dropped" do
      # `all` names are ["queryable", "opts"]; a 3rd arg has no name → renders as value.
      node = boundary(:all, [arg1: :q, arg2: :o, arg3: :extra], :ok)
      short = strip_ansi(Formatter.format([node], show_args: true))
      outline = strip_ansi(Formatter.format([node], detail: :outline))

      assert short =~ "MyApp.Repo.all(queryable: :q, opts: :o, :extra) => :ok"
      refute short =~ "nil:"
      assert outline =~ "MyApp.Repo.all(queryable, opts, :extra)"
      refute outline =~ ", )"
    end

    test "show_args: false → positional values (names suppressed) for boundaries too" do
      node = boundary(:get!, [arg1: MyApp.User, arg2: 1], :ok)
      plain = strip_ansi(Formatter.format([node], show_args: false))
      assert plain =~ "MyApp.Repo.get!(MyApp.User, 1) => :ok"
      refute plain =~ "queryable"
    end
  end

  describe "Ecto noise cleanup wiring" do
    alias CodeStory.TestSupport.{EctoIsh, FakeMeta}

    defp ecto_value do
      %EctoIsh{
        __meta__: %FakeMeta{state: :loaded, source: "orders"},
        id: 12,
        status: "paid",
        kind: "x"
      }
    end

    test "strips noise on a non-leaf return (site 127) and arg values, short_story + novel" do
      for detail <- [:short_story, :novel] do
        tree = [
          %{
            module: MyApp,
            function: :parent,
            args: [order: ecto_value()],
            return: ecto_value(),
            children: [%{module: MyApp, function: :child, args: [], return: :ok, children: []}]
          }
        ]

        out = strip_ansi(Formatter.format(tree, detail: detail))
        refute out =~ "Ecto.Schema.Metadata"
        assert out =~ "EctoIsh"
        assert out =~ "=> MyApp.parent returned"
      end
    end

    test "strips noise on a leaf return (site 180)" do
      tree = [%{module: MyApp, function: :f, args: [], return: ecto_value(), children: []}]
      out = strip_ansi(Formatter.format(tree, detail: :short_story))
      refute out =~ "Ecto.Schema.Metadata"
      assert out =~ "EctoIsh"
    end

    test "strips noise in a boundary signature (site 75; :short_story shows the return)" do
      tree = [
        %{
          module: MyApp.Repo,
          function: :get!,
          args: [q: MyApp.User, id: 1],
          return: ecto_value(),
          children: [],
          boundary: true
        }
      ]

      # :short_story renders the boundary return (:outline drops it), so this is where
      # the returned Ecto value — and its stripped noise — is visible.
      out = strip_ansi(Formatter.format(tree, detail: :short_story))
      refute out =~ "Ecto.Schema.Metadata"
      assert out =~ "MyApp.Repo.get!("
      assert out =~ "EctoIsh"
    end
  end

  describe "inline call signatures" do
    defp lines(output), do: output |> strip_ansi() |> String.split("\n")

    test "fits?: at == width the call inlines; one char over it stacks" do
      node = [%{module: MyApp, function: :f, args: [a: 1], return: 2, children: []}]
      line = "MyApp.f(a: 1) => 2"
      w = String.length(line)

      inline = lines(Formatter.format(node, width: w, show_args: true))
      assert Enum.at(inline, 1) == line

      stacked = lines(Formatter.format(node, width: w - 1, show_args: true))
      assert Enum.at(stacked, 1) == "MyApp.f"
      assert Enum.at(stacked, 2) == "  a: 1"
      assert Enum.at(stacked, 3) == "=> 2"
    end

    test "an over-width leaf falls back to the classic stacked layout" do
      node = [
        %{module: MyApp, function: :process, args: [tag: "hello"], return: :ok, children: []}
      ]

      out = lines(Formatter.format(node, width: 5, show_args: true))
      assert Enum.at(out, 1) == "MyApp.process"
      assert Enum.at(out, 2) == "  tag: \"hello\""
      assert Enum.at(out, 3) == "=> :ok"
    end

    test "a nil return inline renders => ? (not => nil) and stays green" do
      node = [%{module: MyApp, function: :f, args: [x: 1], return: nil, children: []}]
      out = Formatter.format(node, show_args: true)

      assert strip_ansi(out) =~ "MyApp.f(x: 1) => ?"
      refute strip_ansi(out) =~ "=> nil"
      # green is now BOLD green (dual-background legibility)
      assert out =~ "\e[1;32m=> ?\e[0m"
    end

    test "arg modes: named (show_args), positional (no show_args), names-only (:outline)" do
      node = [%{module: MyApp, function: :f, args: [a: 1, b: 2], return: :ok, children: []}]

      assert strip_ansi(Formatter.format(node, show_args: true)) =~ "MyApp.f(a: 1, b: 2) => :ok"
      assert strip_ansi(Formatter.format(node, show_args: false)) =~ "MyApp.f(1, 2) => :ok"

      outline = strip_ansi(Formatter.format(node, detail: :outline))
      assert outline =~ "MyApp.f(a, b)"
      refute outline =~ "=>"
    end

    test ":outline inline non-leaf: signature + children, no return line" do
      tree = [
        %{
          module: MyApp,
          function: :parent,
          args: [a: 1],
          return: :r,
          children: [%{module: MyApp, function: :child, args: [b: 2], return: :c, children: []}]
        }
      ]

      plain = strip_ansi(Formatter.format(tree, detail: :outline))
      assert plain =~ "MyApp.parent(a)\n"
      assert plain =~ "  MyApp.child(b)"
      refute plain =~ "=>"
      refute plain =~ "returned"
    end

    test ":novel: a big struct arg exceeds the budget and stacks" do
      big = %{
        __struct__: MyApp.User,
        name: "Alice Example",
        email: "alice@example.com",
        address: "123 Main Street",
        phone: "555-123-4567",
        role: :administrator
      }

      node = [%{module: MyApp, function: :process, args: [user: big], return: :ok, children: []}]
      out = lines(Formatter.format(node, detail: :novel, show_args: true))
      assert Enum.at(out, 1) == "MyApp.process"
      assert Enum.any?(out, &(&1 =~ "  user: "))
    end

    test "width_for default 100 applies when :width is omitted (direct format/2)" do
      # a call that fits <= 100 inlines with no :width passed
      node = [%{module: MyApp, function: :f, args: [a: 1], return: 2, children: []}]
      assert strip_ansi(Formatter.format(node, [])) =~ "MyApp.f(a: 1) => 2"

      # a call whose line exceeds 100 must STACK with no :width — proves the default
      # is actually applied. (A missing default would leave width nil, and Elixir's
      # `n <= nil` is true, so everything would spuriously inline.)
      long = [
        %{
          module: MyApp,
          function: :process,
          args: [tag: String.duplicate("x", 90)],
          return: :ok,
          children: []
        }
      ]

      assert Enum.at(lines(Formatter.format(long, detail: :novel, show_args: true)), 1) ==
               "MyApp.process"
    end

    test ":width override flips the inline/stacked decision" do
      node = [
        %{
          module: MyApp,
          function: :process,
          args: [tag: "hello world"],
          return: :ok,
          children: []
        }
      ]

      assert Enum.at(lines(Formatter.format(node, width: 200, show_args: true)), 1) ==
               "MyApp.process(tag: \"hello world\") => :ok"

      assert Enum.at(lines(Formatter.format(node, width: 10, show_args: true)), 1) ==
               "MyApp.process"
    end

    test "an inline non-leaf never adds blank separators around its children" do
      tight = [
        %{
          module: MyApp,
          function: :p,
          args: [a: 1],
          return: :r,
          children: [%{module: MyApp, function: :c, args: [b: 2], return: :cc, children: []}]
        }
      ]

      assert strip_ansi(Formatter.format(tight, show_args: true)) =~
               "MyApp.p(a: 1)\n  MyApp.c(b: 2) => :cc\n=> MyApp.p returned :r"

      big = %{
        __struct__: MyApp.User,
        name: "Alice Example",
        email: "alice@example.com",
        address: "123 Main Street",
        phone: "555-123-4567",
        role: :administrator
      }

      loose = [
        %{
          module: MyApp,
          function: :p,
          args: [a: 1],
          return: :r,
          children: [%{module: MyApp, function: :c, args: [user: big], return: :cc, children: []}]
        }
      ]

      # parent p(a: 1) fits inline; child c stacks (big novel struct) — the inline
      # parent still adds NO blank separators (dense, one clean indented tree).
      out = strip_ansi(Formatter.format(loose, detail: :novel, show_args: true))
      assert out =~ "MyApp.p(a: 1)\n  MyApp.c\n"
      refute out =~ "MyApp.p(a: 1)\n\n"
    end

    test "an inline non-leaf at the depth cap shows the marker between signature and return" do
      out = lines(Formatter.format(@deep_tree, show_args: true, depth: 1))
      assert Enum.at(out, 1) == "MyApp.a(x: 1)"
      assert Enum.at(out, 2) == "  … (3 more levels)"
      assert Enum.at(out, 3) == "=> MyApp.a returned :ra"
    end
  end

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
