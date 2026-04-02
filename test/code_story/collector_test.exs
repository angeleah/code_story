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
end
