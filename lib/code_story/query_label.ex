defmodule CodeStory.QueryLabel do
  @moduledoc """
  Compact, framed label for an `Ecto.Query` value — e.g.
  `#Ecto.Query<MyApp.Accounts.User>` — so a query argument in a trace reads as the
  schema it queries instead of a verbose `from … where … order_by …` dump.

  Detection is **value-shaped and dependency-free**: `Ecto.Query`/`Ecto.SubQuery`
  are matched only as atom literals (`%{__struct__: Ecto.Query}`), which compile
  without Ecto being available. `label/1` returns `nil` for any non-query value, so
  callers can fall through to normal inspection.

  ## Known limitation

  Only a **top-level** query value is labelled — a query nested inside a map/list
  argument still inspects verbosely. Boundary arguments are top-level, so this
  covers the common case.
  """

  # NOTE: the `from: %{source: source}` shape is Ecto's *internal* (non-public)
  # representation and can drift across Ecto versions. Every level here degrades to a
  # generic label rather than crashing, and that assumed shape is validated against a
  # real `%Ecto.Query{}` only by an out-of-repo integration test against a real Ecto
  # app — the local unit tests use hand-built maps and cannot detect a shape change.
  @spec label(term()) :: String.t() | nil
  def label(%{__struct__: Ecto.Query, from: %{source: source}}), do: source_label(source)
  def label(%{__struct__: Ecto.Query}), do: "#Ecto.Query<...>"
  def label(_), do: nil

  @spec source_label(term()) :: String.t()
  defp source_label({_table, schema}) when is_atom(schema) and not is_nil(schema),
    do: "#Ecto.Query<" <> CodeStory.ModuleName.short(schema) <> ">"

  # `inspect/1` supplies the quotes and escapes any embedded quote/control char.
  defp source_label({table, nil}) when is_binary(table), do: "#Ecto.Query<#{inspect(table)}>"
  defp source_label(%{__struct__: Ecto.SubQuery}), do: "#Ecto.Query<subquery>"
  defp source_label(_), do: "#Ecto.Query<...>"
end
