# CodeStory

Every codebase has a story. CodeStory lets you read it. Drop `CodeStory.tell()` into a function and see the narrative unfold: which functions are called, with what arguments (by name and value), and what they return — rendered as a nested call tree.

**Use cases:**

- Joining a new codebase and understanding how it actually works
- Tracing call flow before refactoring
- Spotting redundant or unexpected function calls
- Exposing your code's vocabulary and catching ubiquitous language mismatches
- Debugging by seeing exactly where data goes wrong

## Requirements

- **Elixir 1.15+**
- **OTP 27+** — CodeStory uses the session-based `:trace` module introduced in
  OTP 27. On older OTP releases, starting a trace will fail.

## Installation

Add `code_story` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [{:code_story, "~> 0.1.0", only: :dev}]
end
```

Install it as `only: :dev` so that any `CodeStory.tell()` calls you forget to
remove fail to compile in production rather than shipping.

To track the development version instead, point at the repository:

```elixir
defp deps do
  [{:code_story, github: "angeleah/code_story", only: :dev}]
end
```

Or if you've cloned it locally, point to the path on disk:

```elixir
defp deps do
  [{:code_story, path: "../code_story", only: :dev}]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

No `require`, no `use`, no macros. Just `CodeStory.tell()` and `CodeStory.stop()`.

## Usage

Place `CodeStory.tell()` before the code you want to understand and `CodeStory.stop()` after it:

```elixir
def handle_request(params) do
  CodeStory.tell()
  result = process_order(params)
  CodeStory.stop()
  result
end
```

This outputs a nested call tree to the terminal:

```
--- CodeStory Trace ---
process_order
  params: %{items: [...], customer_id: 7}

  validate_item ×3 (varies)
    item: %{sku: "A1", qty: 2}
  => :ok

  calculate_total
    items: [...]
  => 29.97

  Repo.insert!
    changeset: #Ecto.Changeset<...>
  => %Invoice{id: 42}

=> process_order returned %Invoice{id: 42}
--- End Trace ---
```

Each function name appears on its own line, with arguments and return values indented below it. Functions with children are visually separated by blank lines.

A few things happen by default to keep the story readable:

- **Repeated calls fold.** The three `validate_item` calls collapse into one node marked `×3` — or `×3 (varies)` when the calls share a function but differ in their arguments (a single representative call is shown). Turn this off with `fold_repeats: false`.
- **Infrastructure stays at the boundary.** A call into your Ecto repo (`Repo.insert!`) appears as a single node with its arguments and return; the repo's internal Ecto plumbing is hidden. Turn this off with `auto_boundary: false`.

Only your project's own functions appear in the trace. Standard library calls, dependency code, framework-generated functions (like `__struct__/0`, `__changeset__/0`), and CodeStory itself are filtered out automatically.

## Options

All options are passed to `CodeStory.tell/1`:

```elixir
CodeStory.tell(detail: :outline)
CodeStory.tell(detail: :novel, output: :file)
CodeStory.tell(show_args: false, output: :both)
```

- **`detail`** — how much of the story to tell. Default: `:short_story`.
  - `:outline` — function names and argument names only. No values, no returns. Great for seeing the shape of a call flow, spotting boundary crossings, and finding redundant calls.
  - `:short_story` — names, truncated values, and returns. The default — enough detail to follow the plot without getting lost in the data.
  - `:novel` — names with complete, untruncated values and returns. Every detail, nothing elided. Use when you need to see the full picture.

- **`show_args`** — show argument names alongside values. Default: `true`.
  Set to `false` to show values only.

- **`output`** — where to write the trace. Default: `:terminal`.
  `:file` writes to `code_story_trace.log` in your project root (ANSI codes stripped).
  `:both` writes to terminal and file.

- **`auto_boundary`** — treat Ecto repos as _boundary modules_: a repo call
  (e.g. `Repo.get!`) shows as a single node with its arguments and return, but the
  repo's internal Ecto plumbing is hidden. Default: `true`. Set to `false` to
  trace repo internals.

- **`fold_repeats`** — collapse consecutive sibling calls to the same function
  into one node marked `×N` (or `×N (varies)` when the calls share a function but
  differ). Default: `true`. Set to `false` to show every call.

- **`depth`** — cap how many levels the trace nests. A positive integer
  (`depth: 1` shows the entry call only; `depth: 2` adds its direct children, and
  so on); below the cap a node's interior is replaced by a `… (N more levels)`
  marker. Default: `:infinity` (no limit).

## How It Differs from `dbg/2`

|                   | `dbg/2`                                | CodeStory                                                  |
| ----------------- | -------------------------------------- | ---------------------------------------------------------- |
| **Scope**         | Single expression or pipeline          | Span of execution between tell/stop                        |
| **What it shows** | Every intermediate value in a pipeline | Only user-defined function calls (filters out stdlib/deps) |
| **Identity**      | Shows code expressions                 | Shows function names with named arguments                  |
| **Purpose**       | Debug a specific value                 | Hear the story — understand call flow                      |
| **Output**        | Per-expression, inline                 | Buffered, dumped as one cohesive block                     |

## How It Works

1. **Module detection** — reads your `mix.exs` app name and finds all your project's modules
2. **Argument name extraction** — reads Elixir debug info from BEAM files to recover original parameter names, scanning across all function clauses to find the best names
3. **Erlang tracing** — sets up trace sessions on the calling process for your modules
4. **Tree building** — a collector process receives trace events and builds a nested call tree
5. **Formatted output** — the tree is rendered with indentation and ANSI colors, then dumped as one block

## Color Scheme

Terminal output uses ANSI colors for readability:

- **Header/footer** (`--- CodeStory Trace ---`): cyan
- **Function names**: blue
- **Argument names**: yellow
- **Argument values**: default terminal color
- **Return values**: green

## Limitations (v1)

- **Single process only** — traces the calling process. Calls in spawned Tasks, GenServers, etc. are not captured.
- **Modules detected at tell time** — hot-reloaded modules mid-trace won't be traced.
- **Dev only** — installed with `only: :dev`, so leftover `CodeStory.tell()` calls fail to compile in prod.
- **One trace per process** — calling `tell()` while a trace is already active warns and returns an error.

## License

Copyright 2026 Angeleah Daidone

Licensed under the [Apache License, Version 2.0](LICENSE). You may not use this
project except in compliance with the License.
