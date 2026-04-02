defmodule CodeStory.Args do
  @moduledoc """
  Extracts function parameter names from BEAM debug info chunks.
  """

  @doc """
  Builds a lookup map of `{module, function, arity} -> [param_names]`
  for all exported functions in the given modules.

  Falls back to positional arg names (`:arg1`, `:arg2`, etc.) when
  debug info is unavailable.
  """
  def extract(modules) do
    modules
    |> Enum.flat_map(&extract_module/1)
    |> Map.new()
  end

  defp extract_module(module) do
    case get_elixir_debug_info(module) do
      {:ok, definitions} ->
        extract_from_elixir_defs(module, definitions)

      :error ->
        case get_erlang_debug_info(module) do
          {:ok, forms} -> extract_from_erlang_forms(module, forms)
          :error -> fallback_for_module(module)
        end
    end
  end

  # Primary: Elixir AST format — preserves original parameter names
  defp get_elixir_debug_info(module) do
    beam_path = :code.which(module)

    with {:ok, {^module, [{:debug_info, {:debug_info_v1, backend, metadata}}]}} <-
           :beam_lib.chunks(beam_path, [:debug_info]),
         {:ok, %{definitions: definitions}} <-
           backend.debug_info(:elixir_v1, module, metadata, []) do
      {:ok, definitions}
    else
      _ -> :error
    end
  end

  # Fallback: Erlang abstract format
  defp get_erlang_debug_info(module) do
    beam_path = :code.which(module)

    with {:ok, {^module, [{:debug_info, {:debug_info_v1, backend, metadata}}]}} <-
           :beam_lib.chunks(beam_path, [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, module, metadata, []) do
      {:ok, forms}
    else
      _ -> :error
    end
  end

  ## Elixir AST extraction

  defp extract_from_elixir_defs(module, definitions) do
    definitions
    |> Enum.reject(fn {{name, _arity}, _kind, _meta, _clauses} ->
      name == :__info__
    end)
    |> Enum.map(fn {{name, arity}, _kind, _meta, clauses} ->
      param_names = extract_best_params_across_clauses(clauses, arity)
      {{module, name, arity}, param_names}
    end)
  end

  # Try all clauses to find the best parameter name for each position.
  # The first clause may use pattern matching (e.g., %Struct{}) or literals
  # that don't yield a variable name. Later clauses may have simple variable names.
  defp extract_best_params_across_clauses(clauses, arity) do
    # Extract names from each clause (keeping :generated for unknowns)
    all_clause_names =
      Enum.map(clauses, fn {_meta, params, _guards, _body} ->
        params
        |> Enum.with_index()
        |> Enum.map(fn {param, _index} -> extract_elixir_var_name(param) end)
        |> then(fn names ->
          if length(names) == arity, do: names, else: List.duplicate(:generated, arity)
        end)
      end)

    if arity == 0 do
      []
    else
      # For each parameter position, pick the first real name found across clauses
      0..(arity - 1)
      |> Enum.map(fn index ->
        all_clause_names
        |> Enum.map(fn names -> Enum.at(names, index) end)
        |> Enum.find(fn name -> name != :generated end)
        |> case do
          nil -> :"arg#{index + 1}"
          name -> name
        end
      end)
    end
  end

  # Simple variable: {:name, meta, nil} or {:name, meta, context}
  defp extract_elixir_var_name({name, meta, context})
       when is_atom(name) and is_list(meta) and (is_atom(context) or is_nil(context)) do
    if Keyword.get(meta, :generated, false) do
      # Generated vars like x0 from default args — use positional fallback
      :generated
    else
      name
    end
  end

  # Pattern match: try both sides, prefer the non-generated one
  defp extract_elixir_var_name({:=, _meta, [left, right]}) do
    case {extract_elixir_var_name(left), extract_elixir_var_name(right)} do
      {:generated, right_name} -> right_name
      {left_name, _} -> left_name
    end
  end

  defp extract_elixir_var_name(_), do: :generated

  ## Erlang abstract format extraction (fallback)

  defp extract_from_erlang_forms(module, forms) do
    forms
    |> Enum.filter(fn
      {:function, _line, name, _arity, _clauses} when name != :__info__ -> true
      _ -> false
    end)
    |> Enum.map(fn {:function, _line, name, arity, clauses} ->
      param_names = extract_erlang_clause_params(hd(clauses), arity)
      {{module, name, arity}, param_names}
    end)
  end

  defp extract_erlang_clause_params({:clause, _line, params, _guards, _body}, arity) do
    params
    |> Enum.with_index()
    |> Enum.map(fn {param, index} ->
      case extract_erlang_var_name(param) do
        {:ok, name} -> name
        :error -> :"arg#{index + 1}"
      end
    end)
    |> then(fn names ->
      if length(names) == arity, do: names, else: positional_args(arity)
    end)
  end

  defp extract_erlang_var_name({:var, _line, name}) do
    cleaned =
      name
      |> Atom.to_string()
      |> String.replace(~r/^_/, "")
      |> String.replace(~r/@\d+$/, "")

    if cleaned == "" or cleaned == "_" do
      :error
    else
      {:ok, String.to_atom(cleaned)}
    end
  end

  defp extract_erlang_var_name({:match, _line, pattern, _value}) do
    extract_erlang_var_name(pattern)
  end

  defp extract_erlang_var_name(_), do: :error

  ## Shared helpers

  defp fallback_for_module(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, arity} ->
      {{module, name, arity}, positional_args(arity)}
    end)
  end

  defp positional_args(0), do: []

  defp positional_args(arity) do
    Enum.map(1..arity, &:"arg#{&1}")
  end
end
