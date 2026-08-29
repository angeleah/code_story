# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- At `:outline` detail, boundary (`Repo.*`) calls now drop their `=> return`, matching
  user functions — `:outline` is uniformly structure-only. The signature (with values)
  still shows; `:short_story`/`:novel` keep the return.

### Added

- User-defined function calls now render as a compact inline signature —
  `Mod.fun(name: value, …) => return` on one line — when the line fits the new
  `:width` budget (default 100), the same signature style boundary (`Repo.*`)
  calls already use. Longer calls fall back to the previous stacked layout, so a
  trace mixes inline (small calls) and stacked (big ones). `:width` is
  configurable per trace (`CodeStory.tell(fn -> … end, width: 120)`).
- Ecto queries render compactly in traces. An `Ecto.Query` argument to a boundary
  call now reads as `#Ecto.Query<Confab.Registration.Registration>` (the queried
  schema) at the summary detail levels, instead of the full
  `#Ecto.Query<from r0 in …, where: …, order_by: …>` dump; string-table and
  subquery sources render `#Ecto.Query<"table">` / `#Ecto.Query<subquery>`. The
  full query is preserved at `:novel`. No Ecto dependency — detection is structural.
- Ecto struct noise is stripped from inspected values in the trace — a schema's
  `__meta__: #Ecto.Schema.Metadata<…>` bookkeeping and unloaded associations
  (`#Ecto.Association.NotLoaded<…>`) are removed, so a value reads as
  `%Order{id: 12, status: "paid", …}` instead of the full Ecto internals. The
  `%Mod{…}` struct name is preserved, and it works with no Ecto dependency —
  detection is purely string-shaped.

## [0.1.0]

Initial release.

### Added

- `CodeStory.tell/1` and `CodeStory.tell/2` in block form — wrap a call
  (`CodeStory.tell(fn -> process_order(params) end)`) to print its trace and get
  the wrapped call's own result back. Tracing is cleaned up automatically, so no
  `stop/0` is needed, and the wrapper never breaks the code it wraps: if tracing
  cannot start or the trace cannot be displayed, the function still runs and
  still returns its result.
- `CodeStory.tell/0`, `CodeStory.tell/1`, and `CodeStory.stop/0` in manual form —
  bracket a region by hand when a single entry call will not express it, printing
  a nested call tree of user-defined function calls with named arguments and
  return values.
- `CodeStory.narrate/2` — run a function while tracing and get back
  `{result, tree}` as data, without printing.
- `CodeStory.to_encodable/2` — convert a call tree into a JSON-ready,
  dependency-free plain-data structure.
- `:detail` option with three levels — `:outline`, `:short_story` (default), and
  `:novel` — controlling how much of each value is shown.
- `:fold_repeats` (default `true`) — collapses consecutive sibling calls to the
  same function into a single `×N` node.
- `:auto_boundary` (default `true`) — treats Ecto repos as boundary modules,
  hiding their internal plumbing while keeping the call itself visible.
- `:depth` — caps how many levels the rendered trace nests.
- `:output` — write the trace to `:terminal` (default), `:file`, or `:both`.
- `:show_args` — show argument names alongside values (default `true`).

[Unreleased]: https://github.com/angeleah/code_story/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/angeleah/code_story/releases/tag/v0.1.0
