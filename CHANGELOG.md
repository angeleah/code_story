# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial release.

### Added

- `CodeStory.tell/1` and `CodeStory.stop/0` — start and stop a trace, printing a
  nested call tree of user-defined function calls with named arguments and
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
