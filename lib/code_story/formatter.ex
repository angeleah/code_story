defmodule CodeStory.Formatter do
  @moduledoc """
  Renders the call tree as a human-readable, color-coded string.

  Each call renders as a compact inline signature — `Mod.fun(name: value, …) =>
  return` — when the assembled line fits the `:width` budget (default 100),
  falling back to a stacked layout (name / one arg per line / return) when it does
  not. The decision is per-call, so a tree freely mixes inline and stacked nodes;
  deeper nesting has more indentation and stacks sooner. `:novel`'s fully-expanded
  structs almost always exceed the budget and stack.
  """

  # ANSI color codes
  @cyan "\e[36m"
  @blue "\e[34m"
  @yellow "\e[33m"
  @green "\e[32m"
  @magenta "\e[35m"
  @dim "\e[90m"
  @reset "\e[0m"

  # Render options threaded through the whole formatter as one param (was five
  # positional args). Clauses still dispatch by head-matching values on it.
  @type ropts :: %{
          show_args: boolean(),
          detail: atom(),
          inspect_opts: keyword(),
          max_depth: pos_integer() | :infinity,
          width: pos_integer() | :infinity
        }

  @doc """
  Formats the call tree with ANSI colors.
  """
  def format(tree, opts) do
    detail = Keyword.get(opts, :detail, :short_story)

    ropts = %{
      show_args: Keyword.get(opts, :show_args, true),
      detail: detail,
      inspect_opts: CodeStory.CleanInspect.opts_for(detail),
      max_depth: max_depth_for(opts),
      width: width_for(opts)
    }

    lines =
      ["#{@cyan}--- CodeStory Trace ---#{@reset}" | format_nodes(tree, 0, ropts)] ++
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

  # `:width` caps the inline-signature line length; over it, a call renders stacked.
  # The authoritative default lives here (not only in the tell-path merge) because
  # `format/2` is public and called directly. Default 100; `:infinity` (matching
  # `:depth`) never stacks; any other non-positive/non-integer falls back to 100.
  @spec width_for(keyword()) :: pos_integer() | :infinity
  defp width_for(opts) do
    case Keyword.get(opts, :width, 100) do
      :infinity -> :infinity
      n when is_integer(n) and n > 0 -> n
      _ -> 100
    end
  end

  defp format_nodes(nodes, depth, ropts) do
    Enum.flat_map(nodes, fn node -> format_node(node, depth, ropts) end)
  end

  # A boundary call (e.g. an Ecto `Repo.*`) is a black box: ALWAYS rendered as an
  # inline signature — `Mod.fun(v1, v2) => return` — showing argument VALUES and the
  # return, not the (macro-generated, meaningless) positional names. Placed before
  # the :outline/general clauses so it wins in both.
  @spec format_node(map(), non_neg_integer(), ropts()) :: [String.t()]
  defp format_node(%{boundary: true} = node, depth, ropts) do
    opts = ropts.inspect_opts
    value_strings = inspect_args(node.args, opts)
    sig = signature(node, :positional, value_strings)

    line = "#{indent(depth * 2)}#{sig} #{format_return(node.return, opts)}#{count_suffix(node)}"

    # Usually childless (interior suppressed). But the collector attaches a
    # cross-module call made from inside the boundary (e.g. a custom `Ecto.Type`)
    # as a child — render those rather than silently drop them (parity with the
    # encoder, which keeps them).
    [line | format_nodes(node.children, depth + 1, ropts)]
  end

  defp format_node(node, depth, %{detail: :outline} = ropts) do
    sig_line = "#{indent(depth * 2)}#{signature(node, :names_only, [])}#{count_suffix(node)}"

    if fits?(sig_line, ropts.width) do
      # `:outline` has no return line, and the stacked outline never used blank
      # separators — so inline is simply the signature followed by the children.
      [sig_line | outline_children(node, depth, ropts)]
    else
      func_indent = indent(depth * 2)
      arg_lines = stacked_args(node.args, [], indent(depth * 2 + 2), :names_only)
      [func_line(node, func_indent)] ++ arg_lines ++ outline_children(node, depth, ropts)
    end
  end

  defp format_node(node, depth, ropts) do
    if node.children == [] do
      format_leaf(node, depth, ropts)
    else
      format_non_leaf(node, depth, ropts)
    end
  end

  # --- leaf / non-leaf composition (general clause) -------------------------------

  defp format_leaf(node, depth, ropts) do
    arg_mode = arg_mode(ropts)
    value_strings = inspect_args(node.args, ropts.inspect_opts)
    func_indent = indent(depth * 2)
    # Inspect the return ONCE into a `format_return` fragment (handles nil -> `=> ?`
    # and green ANSI), shared by both the inline and stacked forms.
    return_frag = format_return(node.return, ropts.inspect_opts)

    inline_line =
      "#{func_indent}#{signature(node, arg_mode, value_strings)} #{return_frag}#{count_suffix(node)}"

    if fits?(inline_line, ropts.width) do
      [inline_line]
    else
      arg_lines = stacked_args(node.args, value_strings, indent(depth * 2 + 2), arg_mode)
      [func_line(node, func_indent)] ++ arg_lines ++ ["#{func_indent}#{return_frag}"]
    end
  end

  defp format_non_leaf(node, depth, ropts) do
    arg_mode = arg_mode(ropts)
    value_strings = inspect_args(node.args, ropts.inspect_opts)
    func_indent = indent(depth * 2)
    display_name = format_function_name(node)
    # Non-leaf return string inspected once, reused by inline and stacked.
    return_str = do_inspect(node.return, ropts.inspect_opts)
    return_line = "#{func_indent}#{@green}=> #{display_name} returned #{return_str}#{@reset}"
    sig_line = "#{func_indent}#{signature(node, arg_mode, value_strings)}#{count_suffix(node)}"

    if fits?(sig_line, ropts.width) do
      # Inline non-leaf: signature line, children nested directly beneath (no blank
      # separators — the whole trace reads as one dense indented tree), return at the
      # bottom.
      body =
        if show_children?(depth, ropts.max_depth) do
          format_nodes(node.children, depth + 1, ropts)
        else
          [marker_line(depth, node)]
        end

      [sig_line] ++ body ++ [return_line]
    else
      arg_lines = stacked_args(node.args, value_strings, indent(depth * 2 + 2), arg_mode)

      body =
        if show_children?(depth, ropts.max_depth) do
          format_nodes(node.children, depth + 1, ropts)
        else
          [marker_line(depth, node)]
        end

      [func_line(node, func_indent)] ++ arg_lines ++ [""] ++ body ++ [""] ++ [return_line]
    end
  end

  # Children beneath an `:outline` node: [] for a leaf, the depth-cap marker when
  # capped, else the recursively-rendered children.
  defp outline_children(%{children: []}, _depth, _ropts), do: []

  defp outline_children(node, depth, ropts) do
    if show_children?(depth, ropts.max_depth) do
      format_nodes(node.children, depth + 1, ropts)
    else
      [marker_line(depth, node)]
    end
  end

  # --- the shared signature helper ------------------------------------------------

  # `Mod.fun(args)` — blue name, args per `arg_mode`. NO return and NO trailing
  # space; every caller composes the return itself (boundary/leaf inline it via
  # `format_return`; general non-leaf puts it on a bottom line; `:outline` has none).
  @spec signature(map(), :named | :positional | :names_only, [String.t()]) :: String.t()
  defp signature(node, arg_mode, value_strings) do
    cells = node.args |> arg_cells(value_strings, arg_mode) |> Enum.join(", ")
    "#{@blue}#{format_function_name(node)}#{@reset}(#{cells})"
  end

  # One renderer per arg mode for the bare `name: value` cell — single-sourced so the
  # inline signature (cells joined with ", ") and the stacked layout (each cell
  # prefixed with the arg indent) can never silently drift apart.
  @spec arg_cells(keyword(), [String.t()], :named | :positional | :names_only) :: [String.t()]
  defp arg_cells(args, strs, :named) do
    args
    |> Enum.zip(strs)
    |> Enum.map(fn {{name, _v}, s} -> "#{@yellow}#{name}:#{@reset} #{s}" end)
  end

  defp arg_cells(_args, strs, :positional), do: strs

  defp arg_cells(args, _strs, :names_only) do
    Enum.map(args, fn {name, _v} -> "#{@yellow}#{name}#{@reset}" end)
  end

  # `line` fits when its VISIBLE width (ANSI stripped, indentation included) is within
  # `width`. `:infinity` (matching `:depth`) never stacks.
  @spec fits?(String.t(), pos_integer() | :infinity) :: boolean()
  defp fits?(_line, :infinity), do: true
  defp fits?(line, width), do: String.length(strip_ansi(line)) <= width

  # Stacked argument lines — the SAME cells as the inline signature (inspect once),
  # each prefixed with the argument indent.
  defp stacked_args(args, value_strings, arg_indent, arg_mode) do
    args |> arg_cells(value_strings, arg_mode) |> Enum.map(&"#{arg_indent}#{&1}")
  end

  defp inspect_args(args, opts), do: Enum.map(args, fn {_name, v} -> do_inspect(v, opts) end)

  @spec arg_mode(ropts()) :: :named | :positional
  defp arg_mode(%{show_args: true}), do: :named
  defp arg_mode(_ropts), do: :positional

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

  defp format_return(nil, _inspect_opts), do: "#{@green}=> ?#{@reset}"

  defp format_return(value, inspect_opts),
    do: "#{@green}=> #{do_inspect(value, inspect_opts)}#{@reset}"

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

  defp format_function_name(node) do
    "#{CodeStory.ModuleName.short(node.module)}.#{node.function}"
  end

  # The stacked-layout header line — `indent + blue Mod.fun + ×N` — single-sourced
  # across the leaf, non-leaf, and outline stacked branches.
  defp func_line(node, func_indent) do
    "#{func_indent}#{@blue}#{format_function_name(node)}#{@reset}#{count_suffix(node)}"
  end

  defp indent(n), do: String.duplicate(" ", n)

  # Single chokepoint for every value inspection — strips Ecto `__meta__`/`NotLoaded`
  # noise. Every value must be rendered through here, never a raw Kernel call
  # (guarded by test/code_story/no_raw_inspect_test.exs).
  defp do_inspect(value, opts), do: CodeStory.CleanInspect.inspect(value, opts)

  defp strip_ansi(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end
