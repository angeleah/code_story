defmodule CodeStory.Formatter do
  @moduledoc """
  Renders the call tree as a human-readable, color-coded string.
  """

  # ANSI color codes
  @cyan "\e[36m"
  @blue "\e[34m"
  @yellow "\e[33m"
  @green "\e[32m"
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

    lines =
      [
        "#{@cyan}--- CodeStory Trace ---#{@reset}"
        | format_nodes(tree, 0, show_args, detail, inspect_opts)
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

  defp format_nodes(nodes, depth, show_args, detail, inspect_opts) do
    Enum.flat_map(nodes, fn node ->
      format_node(node, depth, show_args, detail, inspect_opts)
    end)
  end

  defp format_node(node, depth, _show_args, :outline, _inspect_opts) do
    func_indent = indent(depth * 2)
    arg_indent = indent(depth * 2 + 2)

    display_name = format_function_name(node.module, node.function)
    func_line = "#{func_indent}#{@blue}#{display_name}#{@reset}"

    arg_lines =
      Enum.map(node.args, fn {name, _value} ->
        "#{arg_indent}#{@yellow}#{name}#{@reset}"
      end)

    child_lines = format_nodes(node.children, depth + 1, true, :outline, [])

    [func_line] ++ arg_lines ++ child_lines
  end

  defp format_node(node, depth, show_args, detail, inspect_opts) do
    func_indent = indent(depth * 2)
    arg_indent = indent(depth * 2 + 2)

    # Function name with module prefix on its own line
    display_name = format_function_name(node.module, node.function)
    func_line = "#{func_indent}#{@blue}#{display_name}#{@reset}"

    # Each arg on its own line, indented 2 from function
    arg_lines = format_args(node.args, arg_indent, show_args, inspect_opts)

    # Children at same indent as args
    child_lines = format_nodes(node.children, depth + 1, show_args, detail, inspect_opts)

    if node.children != [] do
      # Return at same level as function name
      return_line =
        "#{func_indent}#{@green}=> #{display_name} returned #{inspect(node.return, inspect_opts)}#{@reset}"

      [func_line] ++ arg_lines ++ [""] ++ child_lines ++ [""] ++ [return_line]
    else
      # Leaf return at same level as function name
      return_line = "#{func_indent}#{format_return(node.return, inspect_opts)}"
      [func_line] ++ arg_lines ++ [return_line]
    end
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
