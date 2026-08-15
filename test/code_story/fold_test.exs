defmodule CodeStory.FoldTest do
  use ExUnit.Case, async: true

  alias CodeStory.Fold

  # Build a tree node the way the Collector does.
  defp node(mod, fun, args, ret, children \\ []) do
    %{module: mod, function: fun, args: args, return: ret, children: children}
  end

  describe "fold/1 — Tier 1 (identical)" do
    test "folds two identical leaves into one node with count: 2, no :varies" do
      n = node(M, :f, [a: 1], :ok)
      assert [folded] = Fold.fold([n, n])
      assert folded.count == 2
      refute Map.has_key?(folded, :varies)
    end

    test "folds three identical into count: 3" do
      n = node(M, :f, [a: 1], :ok)
      assert [%{count: 3}] = Fold.fold([n, n, n])
    end

    test "folds identical PARENTS with identical children, losslessly (children shown once)" do
      child = node(M, :g, [x: 1], :a)
      parent = node(M, :f, [a: 1], :ok, [child])
      assert [folded] = Fold.fold([parent, parent])
      assert folded.count == 2
      refute Map.has_key?(folded, :varies)
      assert folded.children == [child]
    end
  end

  describe "fold/1 — Tier 2 (varies)" do
    test "folds two same-fn/arity with different args into count: 2, varies: true" do
      run = [node(M, :f, [a: 1], :ok), node(M, :f, [a: 2], :ok)]
      assert [%{count: 2, varies: true}] = Fold.fold(run)
    end

    test "keeps the RICHEST occurrence (most children) as the representative" do
      lean = node(M, :f, [a: 1], :ok, [])
      rich = node(M, :f, [a: 2], :ok, [node(M, :g, [], :x)])
      assert [folded] = Fold.fold([lean, rich])
      assert folded.count == 2 and folded.varies == true
      assert folded.args == [a: 2]
      assert folded.children != []
    end

    test "ranks the representative on PRE-fold child count (foldable children don't shrink the rank)" do
      # `busy` makes 3 identical g-calls; those fold to a single `g ×3` node.
      # `lean` makes 2 distinct calls that stay separate.
      # Post-fold, busy has 1 child and lean has 2 — but busy did MORE actual
      # work, so it must be the representative. Ranking must use pre-fold counts.
      busy =
        node(M, :f, [who: :busy], :ok, [
          node(M, :g, [], 1),
          node(M, :g, [], 1),
          node(M, :g, [], 1)
        ])

      lean = node(M, :f, [who: :lean], :ok, [node(M, :h, [], 1), node(M, :k, [], 2)])

      assert [folded] = Fold.fold([busy, lean])
      assert folded.count == 2 and folded.varies == true
      assert folded.args == [who: :busy]
      # the representative's own children are still folded
      assert [%{function: :g, count: 3}] = folded.children
    end

    test "a run of 3 where only 2 are identical still folds as varies (not all ===)" do
      run = [node(M, :f, [a: 1], :ok), node(M, :f, [a: 1], :ok), node(M, :f, [a: 2], :ok)]
      assert [%{count: 3, varies: true}] = Fold.fold(run)
    end

    test "differs only in a nested child → Tier 2 (bottom-up === composition)" do
      a = node(M, :f, [a: 1], :ok, [node(M, :g, [x: 1], :a)])
      b = node(M, :f, [a: 1], :ok, [node(M, :g, [x: 2], :b)])
      assert [%{count: 2, varies: true}] = Fold.fold([a, b])
    end

    test "=== not ==: 1 vs 1.0 args are NOT identical → Tier 2 (varies), not a clean Tier-1 fold" do
      run = [node(M, :f, [x: 1], :ok), node(M, :f, [x: 1.0], :ok)]
      assert [%{count: 2, varies: true}] = Fold.fold(run)
    end
  end

  describe "fold/1 — non-folding cases" do
    test "same name, different arity is NOT grouped" do
      f1 = node(M, :f, [a: 1], :ok)
      f2 = node(M, :f, [a: 1, b: 2], :ok)
      result = Fold.fold([f1, f2])
      assert length(result) == 2
      refute Enum.any?(result, &Map.has_key?(&1, :count))
    end

    test "distinct functions are not grouped" do
      result = Fold.fold([node(M, :f, [], 1), node(M, :g, [], 2)])
      assert length(result) == 2
      refute Enum.any?(result, &Map.has_key?(&1, :count))
    end

    test "non-consecutive identicals (A B A) are not folded" do
      a = node(M, :a, [], 1)
      b = node(M, :b, [], 2)
      result = Fold.fold([a, b, a])
      assert length(result) == 3
      refute Enum.any?(result, &Map.has_key?(&1, :count))
    end
  end

  describe "fold/1 — recursion & edges" do
    test "folds recursively: repeated children inside repeated parents" do
      child = node(M, :g, [], :x)
      parent = node(M, :f, [a: 1], :ok, [child, child])
      assert [outer] = Fold.fold([parent, parent])
      assert outer.count == 2
      assert [%{count: 2}] = outer.children
    end

    test "empty list folds to empty" do
      assert Fold.fold([]) == []
    end

    test "single node is returned unchanged (no keys)" do
      n = node(M, :f, [a: 1], :ok)
      assert [^n] = Fold.fold([n])
    end

    test "folds a multi-root list (pure-function generality)" do
      n = node(M, :f, [], :ok)
      assert [%{count: 2}] = Fold.fold([n, n])
    end
  end
end
