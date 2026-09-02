defmodule CodeStory.ModuleName do
  @moduledoc false

  # Shared display helper: the short, `Elixir.`-less string form of a module atom,
  # e.g. `MyApp.Accounts.User`. Used by the formatter, the encoder, and QueryLabel
  # so the trace names modules identically everywhere.
  @spec short(module()) :: String.t()
  def short(mod), do: mod |> Atom.to_string() |> String.replace_leading("Elixir.", "")
end
