defmodule CodeStory.Formatter do
  @moduledoc """
  Renders the call tree as a human-readable, color-coded string.
  """

  # ANSI color codes
  @cyan "\e[36m"
  @blue "\e[34m"
  @yellow "\e[33m"
  @green "\e[32m"
  @magenta "\e[35m"
  @dim "\e[90m"
  @reset "\e[0m"

  @compact_inspect_opts [limit: 3, printable_limit: 50, width: 80]
  @full_inspect_opts [limit: :infinity, printable_limit: :infinity]

  @doc """
  Formats the call tree with ANSI colors.
  """
  def format(tree, opts) do
    detail = Keyword.get(opts, :detail, :short_story)
    show_args = Keyword.get(opts, :show_args, true)
    inspect_opts = inspect_opts_for(detail)
    max_depth = max_depth_for(opts)

    lines =
      [
        "#{@cyan}--- CodeStory Trace ---#{@reset}"
        | format_nodes(tree, 0, show_args, detail, inspect_opts, max_depth)
      ] ++
        ["#{@cyan}--- End Trace ---#{@reset}"]

    Enum.join(lines, "\n")
  end

  @doc """
  Formats the call tree without ANSI colors (for file output).
  """
  def format_plain(tree, opts) do
    tree
    |> format(opts)
    |> strip_ansi()
  end

  defp inspect_opts_for(:novel), do: @full_inspect_opts
  defp inspect_opts_for(_), do: @compact_inspect_opts

  # `:depth` caps rendered nesting. Any number is accepted: floats are truncated
  # to an integer and values `< 1` clamp to 1. `:infinity` (and any non-number)
  # means no limit.
  @spec max_depth_for(keyword()) :: pos_integer() | :infinity
  defp max_depth_for(opts) do
    case Keyword.get(opts, :depth, :infinity) do
      n when is_number(n) -> max(trunc(n), 1)
      _ -> :infinity
    end
  end

  defp format_nodes(nodes, depth, show_args, detail, inspect_opts, max_depth) do
    Enum.flat_map(nodes, fn node ->
      format_node(node, depth, show_args, detail, inspect_opts, max_depth)
    end)
  end

  # A boundary call (e.g. an Ecto `Repo.*`) is a black box: render it as an inline
  # call signature — `Mod.fun(v1, v2) => return` — showing argument VALUES and the
  # return, not the (macro-generated, meaningless) positional names. Placed before
  # the :outline/general clauses so it wins in both. Re-derives `inspect_opts` from
  # `detail` because the :outline clause recurses with a hard-coded `[]`.
  @spec format_node(map(), non_neg_integer(), boolean(), atom(), keyword(), any()) :: [String.t()]
  defp format_node(%{boundary: true} = node, depth, show_args, detail, _inspect_opts, max_depth) do
    opts = inspect_opts_for(detail)
    name = format_function_name(node.module, node.function)
    values = node.args |> Enum.map(fn {_name, v} -> inspect(v, opts) end) |> Enum.join(", ")

    line =
      "#{indent(depth * 2)}#{@blue}#{name}#{@reset}(#{values}) " <>
        "#{format_return(node.return, opts)}#{count_suffix(node)}"

    # Usually childless (interior suppressed). But the collector attaches a
    # cross-module call made from inside the boundary (e.g. a custom `Ecto.Type`)
    # as a child — render those rather than silently drop them (parity with the
    # encoder, which keeps them). `opts` (re-derived) is passed so nested values
    # truncate correctly even when this boundary was reached via the :outline path.
    child_lines = format_nodes(node.children, depth + 1, show_args, detail, opts, max_depth)

    [line | child_lines]
  end

  defp format_node(node, depth, _show_args, :outline, _inspect_opts, max_depth) do
    func_indent = indent(depth * 2)
    arg_indent = indent(depth * 2 + 2)

    display_name = format_function_name(node.module, node.function)
    func_line = "#{func_indent}#{@blue}#{display_name}#{@reset}#{count_suffix(node)}"

    arg_lines =
      Enum.map(node.args, fn {name, _value} ->
        "#{arg_indent}#{@yellow}#{name}#{@reset}"
      end)

    child_lines =
      if node.children != [] and not show_children?(depth, max_depth) do
        [marker_line(depth, node)]
      else
        format_nodes(node.children, depth + 1, true, :outline, [], max_depth)
      end

    [func_line] ++ arg_lines ++ child_lines
  end

  defp format_node(node, depth, show_args, detail, inspect_opts, max_depth) do
    func_indent = indent(depth * 2)
    arg_indent = indent(depth * 2 + 2)

    # Function name with module prefix on its own line
    display_name = format_function_name(node.module, node.function)
    func_line = "#{func_indent}#{@blue}#{display_name}#{@reset}#{count_suffix(node)}"

    # Each arg on its own line, indented 2 from function
    arg_lines = format_args(node.args, arg_indent, show_args, inspect_opts)

    if node.children != [] do
      # Return at same level as function name
      return_line =
        "#{func_indent}#{@green}=> #{display_name} returned #{inspect(node.return, inspect_opts)}#{@reset}"

      # At the cap, replace the interior with a single marker line (no recursion).
      body =
        if show_children?(depth, max_depth) do
          format_nodes(node.children, depth + 1, show_args, detail, inspect_opts, max_depth)
        else
          [marker_line(depth, node)]
        end

      [func_line] ++ arg_lines ++ [""] ++ body ++ [""] ++ [return_line]
    else
      # Leaf return at same level as function name — leaves never truncate.
      return_line = "#{func_indent}#{format_return(node.return, inspect_opts)}"
      [func_line] ++ arg_lines ++ [return_line]
    end
  end

  # Show a node's children iff we're above the depth cap. `:infinity` = always.
  @spec show_children?(non_neg_integer(), pos_integer() | :infinity) :: boolean()
  defp show_children?(_depth, :infinity), do: true
  defp show_children?(depth, max_depth), do: depth + 1 < max_depth

  # Depth of the pruned subtree below `node` (levels hidden by truncation).
  @spec levels_below(map()) :: non_neg_integer()
  defp levels_below(%{children: []}), do: 0

  defp levels_below(%{children: children}),
    do: 1 + Enum.max(Enum.map(children, &levels_below/1))

  # The `… (K more level[s])` marker, at child indent. K is always ≥ 1 here.
  @spec marker_line(non_neg_integer(), map()) :: String.t()
  defp marker_line(depth, node) do
    k = levels_below(node)
    unit = if k == 1, do: "level", else: "levels"
    "#{indent((depth + 1) * 2)}#{@dim}… (#{k} more #{unit})#{@reset}"
  end

  defp format_args(args, arg_indent, true, inspect_opts) do
    Enum.map(args, fn {name, value} ->
      "#{arg_indent}#{@yellow}#{name}:#{@reset} #{inspect(value, inspect_opts)}"
    end)
  end

  defp format_args(args, arg_indent, false, inspect_opts) do
    Enum.map(args, fn {_name, value} ->
      "#{arg_indent}#{inspect(value, inspect_opts)}"
    end)
  end

  defp format_return(nil, _inspect_opts), do: "#{@green}=> ?#{@reset}"

  defp format_return(value, inspect_opts),
    do: "#{@green}=> #{inspect(value, inspect_opts)}#{@reset}"

  # A ` ×N` (or ` ×N (varies)`) suffix for a folded node; "" for an ordinary node.
  @spec count_suffix(map()) :: String.t()
  defp count_suffix(node) do
    case Map.get(node, :count, 1) do
      n when n > 1 ->
        varies = if node[:varies], do: " (varies)", else: ""
        " #{@magenta}×#{n}#{varies}#{@reset}"

      _ ->
        ""
    end
  end

  defp format_function_name(module, function) do
    mod_name =
      module
      |> Atom.to_string()
      |> String.replace_leading("Elixir.", "")

    "#{mod_name}.#{function}"
  end

  defp indent(n), do: String.duplicate(" ", n)

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
