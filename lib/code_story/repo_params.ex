defmodule CodeStory.RepoParams do
  @moduledoc false
  # A subset of Ecto.Repo callback parameter names, so boundary (Repo.*) calls render
  # with readable names across the :detail dial instead of positional values. No Ecto
  # dependency — plain strings keyed by function-name atom. Names are merged positionally
  # by index against a call's actual args (the trailing `opts` is picked up only when
  # passed). Unmapped functions return nil -> caller falls back to values.
  #
  # INVARIANT: keyed by function name with NO module, so it assumes every boundary node
  # is an Ecto repo call (boundaries are derived solely from `Modules.ecto_repos/1`). If
  # `:boundary` is ever generalized to other black-box modules, a same-named function
  # (`all`/`get`/`one`) elsewhere would get Repo names misapplied — gate this by module then.
  #
  # `changeset` is a deliberate umbrella over Ecto's `struct_or_changeset` for the
  # write family; a bare struct is the loose case (the value shows the truth), and at
  # :outline the value is hidden — an accepted cost of names-only mode, not a bug.
  @params %{
    get: ["queryable", "id", "opts"],
    get!: ["queryable", "id", "opts"],
    get_by: ["queryable", "filters", "opts"],
    get_by!: ["queryable", "filters", "opts"],
    all: ["queryable", "opts"],
    one: ["queryable", "opts"],
    one!: ["queryable", "opts"],
    insert: ["changeset", "opts"],
    insert!: ["changeset", "opts"],
    update: ["changeset", "opts"],
    update!: ["changeset", "opts"],
    delete: ["changeset", "opts"],
    delete!: ["changeset", "opts"],
    preload: ["struct", "preloads", "opts"]
  }

  @spec names(atom()) :: [String.t()] | nil
  def names(fun), do: Map.get(@params, fun)
end
