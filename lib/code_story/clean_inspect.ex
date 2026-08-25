defmodule CodeStory.CleanInspect do
  @moduledoc """
  Inspects a value, then strips Ecto bookkeeping noise from the resulting string —
  `__meta__: #Ecto.Schema.Metadata<…>` and `#Ecto.Association.NotLoaded<…>` — so a
  trace shows `%Order{id: 12, status: "paid", …}` instead of the full Ecto internals.

  One value-shaped exception precedes the string cleaning: `inspect/2` first
  delegates a top-level `Ecto.Query` value to `CodeStory.QueryLabel`, which renders
  it as a compact `#Ecto.Query<Schema>` label (at the summary detail levels only).
  Everything else follows the string-cleaning path below.

  We clean the **inspected string**, not the value: removing `__meta__` from the
  value pre-inspect turns the struct into a plain map (`%{…, __struct__: Mod}`),
  losing the `%Mod{…}` name. CodeStory has no Ecto dependency — detection is purely
  string-shaped.

  ## Known limitations

  Because this is string-cleaning, not value-cleaning:

    * a struct with `__meta__` as its *only* field isn't stripped (no adjacent `, `) —
      real schemas always have an `id`/fields, so this never happens in practice;
    * a `NotLoaded` association whose name isn't a bare identifier (`\\w+`) isn't
      dropped — rare;
    * a genuine string value that literally contains the full
      `__meta__: #Ecto.Schema.Metadata<…>` field shape would be edited — the
      unavoidable cost of the chosen approach; low likelihood (a bare
      `#Ecto.Schema.Metadata<…>` substring, with no `__meta__:` prefix, is untouched);
    * under a compact `:limit`, stripping a `NotLoaded`/nested-struct field can show
      one fewer real field at that level (only the top-level `__meta__` slot is
      compensated by the limit bump below).
  """

  # Compact vs. full inspect options, keyed to the `:detail` level. Both callers —
  # `CodeStory.Formatter` and `CodeStory.Encoder` — route through `opts_for/1`, so this
  # mapping has a single home rather than a copy in each module kept in sync by comment.
  #
  # INVARIANT: these opts must keep inspect output single-line — the strip regexes below
  # key on a literal `, ` field separator. Do NOT add `pretty: true`: it would wrap wide
  # values onto `,\n` lines and make every strip below silently no-op. (`width` is inert
  # without `pretty`, so it is deliberately omitted here.)
  @compact_inspect_opts [limit: 3, printable_limit: 50]
  @full_inspect_opts [limit: :infinity, printable_limit: :infinity]

  @meta_marker "#Ecto.Schema.Metadata<"
  @meta_first ~r/__meta__: #Ecto\.Schema\.Metadata<[^>]*>, /
  @meta_last ~r/, __meta__: #Ecto\.Schema\.Metadata<[^>]*>/
  @notloaded_first ~r/\w+: #Ecto\.Association\.NotLoaded<[^>]*>, /
  @notloaded_last ~r/, \w+: #Ecto\.Association\.NotLoaded<[^>]*>/

  @doc """
  Like `Kernel.inspect/2`, but with Ecto `__meta__`/`NotLoaded` noise stripped.
  """
  @spec inspect(term(), keyword()) :: String.t()
  def inspect(value, opts) do
    # A top-level Ecto.Query value is labelled compactly (schema summary) at the
    # summary detail levels only. `:novel` is the ONLY level whose opts carry
    # `limit: :infinity` (see `opts_for/1`), so the gate keys on that deliberately:
    # `:novel` keeps the full query. Classify and return BEFORE any `Kernel.inspect`,
    # and never route the label through `strip_ecto_noise/1`.
    compact? = Keyword.get(opts, :limit) != :infinity

    case compact? && CodeStory.QueryLabel.label(value) do
      label when is_binary(label) -> label
      _ -> clean_inspect(value, opts)
    end
  end

  @spec clean_inspect(term(), keyword()) :: String.t()
  defp clean_inspect(value, opts) do
    raw = Kernel.inspect(value, opts)

    # Bump the `:limit` by 1 and re-inspect ONLY when an Ecto `__meta__` field is
    # actually present in the output — since stripping it would otherwise consume a
    # limit slot, leaving one fewer REAL field visible in the compact view. Gating on
    # the rendered marker (not on a `%{__meta__: _}` key match) means a plain map that
    # merely happens to carry a `__meta__` key — with no Ecto metadata to strip — is
    # left untouched and never over-counts its fields.
    if String.contains?(raw, @meta_marker) do
      value |> Kernel.inspect(bump_limit(opts)) |> strip_ecto_noise()
    else
      strip_ecto_noise(raw)
    end
  end

  @doc """
  Inspect options for a `:detail` level — full values for `:novel`, compact otherwise.
  The single source of truth both the formatter and the encoder resolve `:detail` through.
  """
  @spec opts_for(atom()) :: keyword()
  def opts_for(:novel), do: @full_inspect_opts
  def opts_for(_detail), do: @compact_inspect_opts

  @doc """
  Removes Ecto `__meta__` and `NotLoaded` fragments from an already-inspected string.
  """
  @spec strip_ecto_noise(String.t()) :: String.t()
  def strip_ecto_noise(str) do
    str
    |> String.replace(@meta_first, "")
    |> String.replace(@meta_last, "")
    |> String.replace(@notloaded_first, "")
    |> String.replace(@notloaded_last, "")
  end

  # Bump an integer `:limit` by 1 (leave `:infinity`/absent alone). Applied only when
  # `inspect/2` has confirmed an Ecto `__meta__` field is present to be stripped.
  @spec bump_limit(keyword()) :: keyword()
  defp bump_limit(opts) do
    case Keyword.get(opts, :limit) do
      n when is_integer(n) -> Keyword.put(opts, :limit, n + 1)
      _ -> opts
    end
  end
end
