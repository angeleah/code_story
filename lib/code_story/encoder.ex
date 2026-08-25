defmodule CodeStory.Encoder do
  @moduledoc """
  Converts a call tree into a JSON-ready plain-data structure.

  The tree from `CodeStory.narrate/2` is a list of
  `%{module, function, args, return, children}` node maps (folded nodes may also
  carry `count:`/`varies:`). `encode/2` turns that into a list of plain maps whose
  values are only strings / numbers / booleans / nil / lists / maps — so
  `JSON.encode!/1` (Elixir 1.18+) or `Jason.encode!/1` works without any change.

  Compaction is opt-in — the default is a faithful, complete encode:

    * `:fold_repeats` (default `false`) — collapse repeated sibling runs via
      `CodeStory.Fold`; folded nodes surface `count`/`varies` fields.
    * `:depth` (default `:infinity`) — cap nesting. At the cap a node encodes
      `children: []` and `truncated: <levels hidden>` (the data-native mirror of
      the formatter's `… (N more levels)` marker).
    * `:detail` (default `:novel`) — value verbosity. `:novel` keeps full values;
      any other value (`:short_story`, `:outline`) uses the compact inspect opts.
  """

  @type node_map :: %{
          required(:module) => module(),
          required(:function) => atom(),
          required(:args) => keyword(),
          required(:return) => any(),
          required(:children) => [node_map()],
          optional(:count) => pos_integer(),
          optional(:varies) => true
        }

  @spec encode([node_map()], keyword()) :: [map()]
  def encode(tree, opts \\ []) do
    tree = if Keyword.get(opts, :fold_repeats, false), do: CodeStory.Fold.fold(tree), else: tree
    detail = Keyword.get(opts, :detail, :novel)
    max_depth = max_depth_for(opts)
    encode_nodes(tree, 1, detail, max_depth)
  end

  defp encode_nodes(nodes, level, detail, max_depth) do
    Enum.map(nodes, &encode_node(&1, level, detail, max_depth))
  end

  defp encode_node(node, level, detail, max_depth) do
    base = %{
      module: module_string(node.module),
      function: Atom.to_string(node.function),
      arity: length(node.args),
      args: encode_args(node.args, detail),
      return: inspect_value(node.return, detail)
    }

    base
    |> maybe_put(:count, Map.get(node, :count))
    |> maybe_put(:varies, Map.get(node, :varies))
    |> put_children(node, level, detail, max_depth)
  end

  # Mirror of CodeStory.Formatter's depth cap (there: 0-based `depth + 1 < max`;
  # here: 1-based `level < max`). Keep the two in sync.
  defp put_children(encoded, %{children: []}, _level, _detail, _max_depth) do
    Map.put(encoded, :children, [])
  end

  defp put_children(encoded, node, level, detail, max_depth) do
    if show_children?(level, max_depth) do
      Map.put(encoded, :children, encode_nodes(node.children, level + 1, detail, max_depth))
    else
      encoded
      |> Map.put(:children, [])
      |> Map.put(:truncated, levels_below(node))
    end
  end

  defp encode_args(args, detail) do
    Enum.map(args, fn {name, value} ->
      %{name: Atom.to_string(name), value: inspect_value(value, detail)}
    end)
  end

  # --- shared tree/depth helpers (twins of CodeStory.Formatter's private copies) ---

  @spec max_depth_for(keyword()) :: pos_integer() | :infinity
  defp max_depth_for(opts) do
    case Keyword.get(opts, :depth, :infinity) do
      n when is_number(n) -> max(trunc(n), 1)
      _ -> :infinity
    end
  end

  @spec show_children?(pos_integer(), pos_integer() | :infinity) :: boolean()
  defp show_children?(_level, :infinity), do: true
  defp show_children?(level, max_depth), do: level < max_depth

  @spec levels_below(map()) :: non_neg_integer()
  defp levels_below(%{children: []}), do: 0

  defp levels_below(%{children: children}),
    do: 1 + Enum.max(Enum.map(children, &levels_below/1))

  defp inspect_value(value, detail),
    do: CodeStory.CleanInspect.inspect(value, CodeStory.CleanInspect.opts_for(detail))

  defp module_string(module) do
    module
    |> Atom.to_string()
    |> String.replace_leading("Elixir.", "")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
