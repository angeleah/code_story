defmodule CodeStory.NarrateTest do
  use ExUnit.Case, async: false

  alias CodeStory.TestSupport.SampleApp

  setup do
    on_exit(fn ->
      CodeStory.Tracer.stop_tracing()

      case Process.get(:code_story_collector) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid)
      end

      Process.delete(:code_story_collector)
      File.rm("code_story_trace.log")
    end)

    :ok
  end

  # Flatten every node in the tree into a list.
  defp all_nodes(tree), do: Enum.flat_map(tree, fn n -> [n | all_nodes(n.children)] end)
  defp functions(tree), do: tree |> all_nodes() |> Enum.map(& &1.function)

  describe "narrate/2 return value" do
    test "returns {result, tree}; result is the fn's value" do
      {result, _tree} = CodeStory.narrate(fn -> SampleApp.add_sub_mult(3, 2) end)
      assert result == 20
    end

    test "tree root has the node shape and a real (non-nil) return" do
      {_r, tree} = CodeStory.narrate(fn -> SampleApp.add_sub_mult(3, 2) end)
      assert [root | _] = tree
      assert Map.keys(root) |> Enum.sort() == [:args, :children, :function, :module, :return]
      assert root.function == :add_sub_mult
      # Proves fetch_tree waited for :completed rather than returning a partial tree.
      assert root.return == 20
    end
  end

  describe "narrate/2 returns the RAW (un-folded) tree" do
    test "repeated sibling calls appear N times and are not folded" do
      {_r, tree} = CodeStory.narrate(fn -> SampleApp.repeat_add(2) end)
      assert [root] = tree
      assert root.function == :repeat_add

      adds = Enum.filter(root.children, &(&1.function == :add))
      assert length(adds) == 3
      refute Enum.any?(all_nodes(tree), &Map.has_key?(&1, :count))

      # Load-bearing: folding WOULD collapse them, so the raw tree is pre-fold.
      folded = CodeStory.Fold.fold(root.children)
      assert Enum.any?(folded, &(Map.get(&1, :count) == 3))
    end
  end

  describe "narrate/2 lifecycle & cleanup" do
    test "leaves no active trace on success; tell/stop works afterward" do
      {_r, _t} = CodeStory.narrate(fn -> SampleApp.add(1, 2) end)
      assert Process.get(:code_story_collector) == nil
      assert :ok = CodeStory.tell()
      CodeStory.stop()
    end

    test "re-raises and cleans up when fun raises" do
      assert_raise RuntimeError, "boom", fn ->
        CodeStory.narrate(fn -> raise "boom" end)
      end

      assert Process.get(:code_story_collector) == nil
    end

    test "a fun with no traced calls returns {result, []}" do
      assert {:bare, []} = CodeStory.narrate(fn -> :bare end)
    end

    test "raises if a trace is already active on the process" do
      :ok = CodeStory.tell()

      assert_raise ArgumentError, fn ->
        CodeStory.narrate(fn -> SampleApp.add(1, 1) end)
      end

      CodeStory.stop()
    end
  end

  describe "narrate/2 trace-time options" do
    test "auto_boundary hides repo internals by default, exposes them when false" do
      {_r, hidden} = CodeStory.narrate(fn -> SampleApp.fetch_via_repo(7) end)
      refute :build_result in functions(hidden)

      {_r, shown} =
        CodeStory.narrate(fn -> SampleApp.fetch_via_repo(7) end, auto_boundary: false)

      assert :build_result in functions(shown)
    end

    test "captures only the first top-level call (freeze-after-first)" do
      {result, tree} =
        CodeStory.narrate(fn ->
          SampleApp.add(1, 1)
          SampleApp.add_sub_mult(3, 2)
        end)

      assert result == 20
      assert [root] = tree
      assert root.function == :add
    end
  end
end
