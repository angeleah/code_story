defmodule CodeStory.Modules do
  @moduledoc """
  Auto-detects user-defined modules from the host project's mix.exs app name.
  """

  @doc """
  Converts an app atom to its expected module prefix string.

  ## Examples

      iex> CodeStory.Modules.camelize_app_name(:my_app)
      "MyApp"
  """
  def camelize_app_name(app) when is_atom(app) do
    app
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc """
  Detects user-defined modules from the current Mix project.

  Returns a list of modules whose top-level namespace matches the
  app name from `Mix.Project.config()[:app]`.
  """
  def detect do
    app = Mix.Project.config()[:app]
    prefix = camelize_app_name(app)

    :code.all_available()
    |> Enum.map(fn {mod_charlist, _path, _loaded} -> List.to_atom(mod_charlist) end)
    |> Enum.filter(&elixir_module?/1)
    |> Enum.filter(fn mod ->
      hd(Module.split(mod)) == prefix
    end)
    |> Enum.reject(&code_story_module?/1)
  end

  @code_story_modules [
    CodeStory,
    CodeStory.Modules,
    CodeStory.Args,
    CodeStory.Collector,
    CodeStory.Tracer,
    CodeStory.Formatter
  ]

  defp code_story_module?(mod) do
    mod in @code_story_modules
  end

  defp elixir_module?(mod) do
    # Elixir modules are atoms starting with "Elixir."
    # Erlang modules like :proplists, :ets, etc. do not have this prefix
    mod |> Atom.to_string() |> String.starts_with?("Elixir.")
  end
end
