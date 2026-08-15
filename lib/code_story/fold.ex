defmodule CodeStory.Fold do
  @moduledoc """
  Collapses consecutive sibling runs of the same `{module, function, arity}` in a
  call tree.

  A run of N ≥ 2 identical subtrees (deep `===`) folds losslessly to one node with
  `count: N`. A run that shares a function/arity but differs folds to the *richest*
  occurrence (most direct child calls, counted before those children are folded)
  with `count: N, varies: true` — a lossy summary that keeps the shape of one
  real call. Runs of 1 are untouched (no keys added), so a
  tree with no repetition is unchanged.
  """

  @type node_map :: %{
          required(:module) => module(),
          required(:function) => atom(),
          required(:args) => list(),
          required(:return) => any(),
          required(:children) => [node_map()],
          optional(:count) => pos_integer(),
          optional(:varies) => true
        }

  @doc """
  Folds consecutive identical / same-function sibling runs, bottom-up.
  """
  @spec fold([node_map()]) :: [node_map()]
  def fold(nodes) do
    nodes
    |> Enum.chunk_by(fn n -> {n.module, n.function, length(n.args)} end)
    |> Enum.map(&collapse_run/1)
  end

  # Runs of 1 are untouched apart from folding their own children.
  @spec collapse_run([node_map()]) :: node_map()
  defp collapse_run([single]), do: fold_children(single)

  defp collapse_run([first | _] = run) do
    if Enum.all?(run, &(&1 === first)) do
      # Tier 1 — every subtree is identical; keep one, count the run.
      first |> fold_children() |> Map.put(:count, length(run))
    else
      # Tier 2 — same function/arity but differing; keep the richest occurrence.
      # Rank on each candidate's *pre-fold* child count so that a call whose
      # children later fold (e.g. `g ×3` → one node) isn't unfairly outranked
      # by a call with fewer, non-folding children.
      run
      |> Enum.max_by(&length(&1.children))
      |> fold_children()
      |> Map.put(:count, length(run))
      |> Map.put(:varies, true)
    end
  end

  @spec fold_children(node_map()) :: node_map()
  defp fold_children(node), do: %{node | children: fold(node.children)}
end
