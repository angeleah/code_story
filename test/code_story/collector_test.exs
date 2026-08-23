defmodule CodeStory.CollectorTest do
  use ExUnit.Case, async: true

  alias CodeStory.Collector

  @args_map %{
    {MyApp, :add, 2} => [:num1, :num2],
    {MyApp, :greet, 1} => [:name]
  }

  @opts [show_args: true, output: :terminal]

  defp start_collector(opts \\ []) do
    caller = self()
    args_map = Keyword.get(opts, :args_map, @args_map)
    collector_opts = Keyword.get(opts, :opts, @opts)
    {:ok, pid} = Collector.start(caller, args_map, collector_opts)
    pid
  end

  describe "start/3" do
    test "starts a collector process" do
      pid = start_collector()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "is not linked to caller" do
      pid = start_collector()
      # If it were linked, this info would show the caller in links
      info = Process.info(pid, :links)
      assert info == {:links, []}
      GenServer.stop(pid)
    end
  end

  describe "trace_progress (narrate's completion signal)" do
    test "reports call-free, then in-progress, then completed" do
      pid = start_collector()

      # No events yet: tracing, no call seen — narrate uses this to detect a
      # genuinely call-free fun.
      assert {:tracing, false} = GenServer.call(pid, :trace_progress)

      # A call has arrived but not yet returned: tracing, call seen. narrate must
      # keep waiting here rather than concluding the tree is empty.
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      assert {:tracing, true} = GenServer.call(pid, :trace_progress)

      # After the top-level return: completed, with the built tree.
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})
      assert {:completed, [%{function: :add}]} = GenServer.call(pid, :trace_progress)

      GenServer.stop(pid)
    end
  end

  describe "trace events" do
    test "builds a tree from call and return_from events" do
      pid = start_collector()

      # Simulate: add(3, 2) -> 5
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})

      {:completed, tree, _opts} = GenServer.call(pid, :get_result)

      assert length(tree) == 1
      [node] = tree
      assert node.module == MyApp
      assert node.function == :add
      assert node.args == [num1: 3, num2: 2]
      assert node.return == 5
      assert node.children == []
    end

    test "builds nested tree from parent/child calls" do
      pid = start_collector()

      # Simulate: greet("world") calls add(1, 2) -> 3, then returns "hello"
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :greet, ["world"]}}})
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [1, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 3}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :greet, 1}, "hello"}})

      {:completed, tree, _opts} = GenServer.call(pid, :get_result)

      [root] = tree
      assert root.function == :greet
      assert root.return == "hello"
      assert length(root.children) == 1

      [child] = root.children
      assert child.function == :add
      assert child.return == 3
    end

    test "auto-stops when stack becomes empty" do
      pid = start_collector()

      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})

      # Need to wait for casts to be processed
      # Use a call to synchronize
      {:completed, _tree, _opts} = GenServer.call(pid, :get_result)

      # Collector should still be alive after auto-stop
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "ignores events after auto-stop" do
      pid = start_collector()

      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})

      # This event arrives after auto-stop — should be ignored
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [10, 20]}}})

      {:completed, tree, _opts} = GenServer.call(pid, :get_result)
      assert length(tree) == 1
      GenServer.stop(pid)
    end

    test "enriches args with names from args_map" do
      pid = start_collector()

      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert node.args == [num1: 3, num2: 2]
    end

    test "uses positional args when function not in args_map" do
      pid = start_collector()

      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :unknown, [1, 2, 3]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :unknown, 3}, :ok}})

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert node.args == [arg1: 1, arg2: 2, arg3: 3]
    end

    test "filters out dunder functions (__name__)" do
      pid = start_collector()

      # Parent call
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :changeset, ["attrs"]}}})
      # Dunder child calls that should be filtered
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :__changeset__, []}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :__changeset__, 0}, %{}}})
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :__struct__, []}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :__struct__, 0}, %{}}})
      # Parent returns
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :changeset, 1}, :ok}})

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert node.function == :changeset
      assert node.children == []
    end
  end

  describe "boundary modules" do
    # `Repo` is the boundary module; `MyApp` is domain code. Bare atoms — the
    # collector only compares module equality.
    defp boundary_collector do
      start_collector(opts: [boundaries: [Repo], show_args: true])
    end

    defp cast_events(pid, events) do
      Enum.each(events, &GenServer.cast(pid, {:trace_event, &1}))
    end

    test "1. suppresses a boundary module's interior calls (plumbing)" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {Repo, :get!, [User, 1, []]}},
        {:call, {Repo, :prepare_opts, [:all, []]}},
        {:return_from, {Repo, :prepare_opts, 2}, []},
        {:return_from, {Repo, :get!, 3}, :the_user},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, tree, _opts} = GenServer.call(pid, :get_result)
      assert [node] = tree
      assert node.module == Repo and node.function == :get!
      assert node.children == []
    end

    test "2. suppresses the arity-delegation chain (all/1 -> all/2)" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :all, [:query]}},
        {:call, {Repo, :all, [:query, []]}},
        {:return_from, {Repo, :all, 2}, [:a, :b]},
        {:return_from, {Repo, :all, 1}, [:a, :b]}
      ])

      {:completed, tree, _opts} = GenServer.call(pid, :get_result)
      assert [node] = tree
      assert node.function == :all
      assert node.children == []
    end

    test "3. keeps the entry node with its args and return" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {Repo, :get!, [User, 1, []]}},
        {:return_from, {Repo, :get!, 3}, :the_user},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert node.args == [arg1: User, arg2: 1]
      assert node.return == :the_user
    end

    test "4. preserves a back-out to domain code as a direct child" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {MyApp, :cast, ["x"]}},
        {:return_from, {MyApp, :cast, 1}, :casted},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert [child] = node.children
      assert child.module == MyApp and child.function == :cast
    end

    test "5. [C1] back-out returning THROUGH a sentinel does not crash and attaches correctly" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {Repo, :get!, [User, 1, []]}},
        {:call, {MyApp, :cast, ["x"]}},
        {:return_from, {MyApp, :cast, 1}, :casted},
        {:return_from, {Repo, :get!, 3}, :the_user},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert node.function == :get!
      assert [child] = node.children
      assert child.module == MyApp and child.function == :cast
      assert Process.alive?(pid)
    end

    test "6. leaves the stack empty and completed after a boundary sequence" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {Repo, :get!, [User, 1, []]}},
        {:return_from, {Repo, :get!, 3}, :the_user},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, _tree, _opts} = GenServer.call(pid, :get_result)
      assert :sys.get_state(pid).stack == []
    end

    test "7. regression: boundaries: [] leaves the interior calls untouched" do
      pid = start_collector(opts: [boundaries: [], show_args: true])

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {Repo, :get!, [User, 1, []]}},
        {:return_from, {Repo, :get!, 3}, :the_user},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert [child] = node.children
      assert child.function == :get!
    end

    test "8. suppresses a boundary call made by backed-out domain code" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [User, 1]}},
        {:call, {MyApp, :process, [:x]}},
        {:call, {Repo, :other, [:y]}},
        {:return_from, {Repo, :other, 1}, :z},
        {:return_from, {MyApp, :process, 1}, :done},
        {:return_from, {Repo, :get!, 2}, :the_user}
      ])

      {:completed, [node], _opts} = GenServer.call(pid, :get_result)
      assert [child] = node.children
      assert child.module == MyApp and child.function == :process
      assert child.children == []
    end
  end

  describe "get_result" do
    test "returns tracing status when still active" do
      pid = start_collector()

      # Push a call but don't complete it
      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})

      # Synchronize — send a call that arrives after the cast
      result = GenServer.call(pid, :get_result)

      assert {:tracing, tree, _opts} = result
      # incomplete call still on stack, not in tree
      assert length(tree) == 0
      GenServer.stop(pid)
    end

    test "returns options alongside tree" do
      pid = start_collector()

      GenServer.cast(pid, {:trace_event, {:call, {MyApp, :add, [3, 2]}}})
      GenServer.cast(pid, {:trace_event, {:return_from, {MyApp, :add, 2}, 5}})

      {:completed, _tree, opts} = GenServer.call(pid, :get_result)
      assert opts[:show_args] == true
      assert opts[:output] == :terminal
      GenServer.stop(pid)
    end
  end

  describe "caller monitoring" do
    test "stops when caller process exits" do
      collector =
        Task.async(fn ->
          # Start collector from this task process (which will exit)
          {:ok, pid} = Collector.start(self(), @args_map, @opts)
          pid
        end)

      pid = Task.await(collector)
      # Give the collector time to receive the DOWN message
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "boundary tagging" do
    # Reuses `boundary_collector/0` (boundaries: [Repo]) and `cast_events/2` from
    # the "boundary modules" describe above.
    test "tags a boundary-module entry call with boundary: true" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {Repo, :get!, [MyApp.User, 1]}},
        {:return_from, {Repo, :get!, 2}, %{id: 1}}
      ])

      {:completed, [node], _} = GenServer.call(pid, :get_result)
      assert node.boundary == true
      assert node.children == []
      GenServer.stop(pid)
    end

    test "a non-boundary call has no :boundary key" do
      pid = boundary_collector()

      cast_events(pid, [
        {:call, {MyApp, :add, [1, 2]}},
        {:return_from, {MyApp, :add, 2}, 3}
      ])

      {:completed, [node], _} = GenServer.call(pid, :get_result)
      refute Map.has_key?(node, :boundary)
      GenServer.stop(pid)
    end

    test "a boundary's interior calls are suppressed; only the entry is tagged" do
      pid = boundary_collector()

      # entry, then a Repo→Repo interior call (boundary already an ancestor)
      cast_events(pid, [
        {:call, {Repo, :get!, [MyApp.User, 1]}},
        {:call, {Repo, :get!, [MyApp.User, 1, []]}},
        {:return_from, {Repo, :get!, 3}, %{id: 1}},
        {:return_from, {Repo, :get!, 2}, %{id: 1}}
      ])

      {:completed, [node], _} = GenServer.call(pid, :get_result)
      assert node.boundary == true
      assert node.children == []
      GenServer.stop(pid)
    end

    test "a dunder fn on a boundary module is skipped, never tagged (cond order lock)" do
      pid = boundary_collector()

      # real entry wrapping a dunder call on the boundary module
      cast_events(pid, [
        {:call, {MyApp, :run, []}},
        {:call, {Repo, :__adapter__, []}},
        {:return_from, {Repo, :__adapter__, 0}, :adapter},
        {:return_from, {MyApp, :run, 0}, :ok}
      ])

      {:completed, [node], _} = GenServer.call(pid, :get_result)
      assert node.function == :run
      # the dunder was skipped — no boundary node created as a child
      assert node.children == []
      GenServer.stop(pid)
    end
  end
end
