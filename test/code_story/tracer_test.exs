defmodule CodeStory.TracerTest do
  use ExUnit.Case, async: false

  alias CodeStory.{Collector, Tracer}

  @args_map %{}
  @opts [show_args: true, output: :terminal]

  describe "start_tracing/3" do
    test "enables tracing for given modules" do
      {:ok, collector} = Collector.start(self(), @args_map, @opts)

      assert :ok = Tracer.start_tracing(collector, [CodeStory.TestSupport.SampleModule], self())

      Tracer.stop_tracing()
      GenServer.stop(collector)
    end
  end

  describe "stop_tracing/0" do
    test "is idempotent" do
      {:ok, collector} = Collector.start(self(), @args_map, @opts)
      :ok = Tracer.start_tracing(collector, [CodeStory.TestSupport.SampleModule], self())

      assert :ok = Tracer.stop_tracing()
      assert :ok = Tracer.stop_tracing()

      GenServer.stop(collector)
    end

    test "works when no tracing was ever started" do
      assert :ok = Tracer.stop_tracing()
    end
  end

  describe "trace events reach collector" do
    test "call and return events are forwarded to collector" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      {:ok, collector} = Collector.start(self(), args_map, @opts)

      test_pid = self()

      pid =
        spawn(fn ->
          receive do
            :go ->
              result = CodeStory.TestSupport.SampleModule.add(3, 2)
              send(test_pid, {:result, result})
              Process.sleep(100)
          end
        end)

      :ok = Tracer.start_tracing(collector, [CodeStory.TestSupport.SampleModule], pid)

      send(pid, :go)
      assert_receive {:result, 5}, 1000
      Process.sleep(50)

      {:completed, tree, _opts} = GenServer.call(collector, :get_result)
      assert length(tree) == 1

      [node] = tree
      assert node.module == CodeStory.TestSupport.SampleModule
      assert node.function == :add
      assert node.return == 5

      Tracer.stop_tracing()
      GenServer.stop(collector)
    end

    test "enriches args with names" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      {:ok, collector} = Collector.start(self(), args_map, @opts)

      test_pid = self()

      pid =
        spawn(fn ->
          receive do
            :go ->
              result = CodeStory.TestSupport.SampleModule.add(10, 20)
              send(test_pid, {:result, result})
              Process.sleep(100)
          end
        end)

      :ok = Tracer.start_tracing(collector, [CodeStory.TestSupport.SampleModule], pid)

      send(pid, :go)
      assert_receive {:result, 30}, 1000
      Process.sleep(50)

      {:completed, [node], _opts} = GenServer.call(collector, :get_result)
      assert node.args == [num1: 10, num2: 20]
      assert node.return == 30

      Tracer.stop_tracing()
      GenServer.stop(collector)
    end
  end
end
