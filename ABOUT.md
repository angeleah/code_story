# CodeStory: Hear the Story Your Code Tells

You just joined a new team. There's a Phoenix app with dozens of modules, a handful of contexts, and a request flow that touches six files before anything hits the database. Someone points you at `OrderController.create/2` and says "start here."

Now what?

You could grep. You could read every module top to bottom. You could set breakpoints and step through. But none of that gives you the big picture — the shape of what happens when a request flows through the system.

**CodeStory does.**

## What Is CodeStory?

CodeStory is a code comprehension tool for Elixir that lets your code tell its own story. It shows you the _narrative_ of a code path: which functions call which, with what arguments, and what comes back. You control how much detail you get — from a quick outline of the plot to the full novel with every value unabridged.

Drop two lines into any function:

```elixir
def create(conn, params) do
  CodeStory.tell()
  result = Orders.create_order(params)
  CodeStory.stop()
  # ...
end
```

And CodeStory produces a call tree like this:

```
--- CodeStory Trace ---
MyApp.Orders.create_order(params: %{item: "widget", qty: 3})
  MyApp.Orders.validate(params: %{item: "widget", qty: 3}) => :ok
  MyApp.Pricing.calculate_total(item: "widget", qty: 3) => 29.97
  MyApp.Invoices.create(item: "widget", total: 29.97) => %MyApp.Invoice{id: 42}
=> MyApp.Orders.create_order returned %MyApp.Invoice{id: 42}
--- End Trace ---
```

That's it. One cohesive snapshot of everything that happened, with only your project's code — no standard library noise, no framework internals, no dependency calls cluttering the view.

## Three Ways to Listen

CodeStory tells the story at the level of detail you need:

**`:outline`** — Just the structure. Function names and argument names, no values, no returns. Like reading the chapter headings of a book — you see the shape of the call flow, which modules are involved, where boundaries get crossed, and where the same function appears suspiciously often.

```elixir
CodeStory.tell(detail: :outline)
```

**`:short_story`** — The default. Names, truncated values, and returns. Enough to follow the plot — you see what data flows where without drowning in large structs or maps.

```elixir
CodeStory.tell()
```

**`:novel`** — Everything. Complete, untruncated values at every level. When you need to see the exact contents of that nested map or the full struct being passed around.

```elixir
CodeStory.tell(detail: :novel)
```

## Why CodeStory?

### Getting up to speed

Every developer who joins an existing project faces the same challenge: understanding how the code actually behaves, not just how it's structured. File trees and module names tell you where things live, but not how they work together.

CodeStory bridges that gap. Point it at any entry point and you immediately see the call flow, the data transformations, and the module boundaries the code crosses.

### The refactoring problem

Before you can safely change code, you need to understand it. "What gets called from here?" is a question that static analysis answers poorly in a dynamic language like Elixir, where behaviours, protocols, and runtime dispatch are common.

CodeStory gives you the runtime truth. Run the function, see exactly what happened — including which modules were involved and in what order.

### The debugging problem

A function returns the wrong value, and you're not sure where things went sideways. You could sprinkle `IO.inspect` calls through a dozen functions, run it, read the interleaved output, then clean them all up. Or you could wrap the entry point with CodeStory and see every function's inputs and outputs in one structured trace. The bug reveals itself — you can see exactly which function received good data and returned bad data.

### Spotting unnecessary calls

Sometimes the call tree reveals things you wouldn't notice by reading code. A function that calls `get_team_id()` four times when once would do. A preload that fires on every iteration of a loop. A helper that gets invoked hundreds of times inside what should be a simple query. CodeStory makes these patterns jump off the screen — especially in `:outline` mode, where repeated function names stack up visually and redundant calls become obvious.

### Exposing your code's vocabulary

Code is language, and inconsistent language breeds confusion. When one module calls it a `contact` and another calls it a `recipient`, when a `template` becomes a `campaign` halfway through the call tree, when `batch_size` and `page_size` mean the same thing — those mismatches signal a domain model that hasn't settled. CodeStory surfaces this naturally. An `:outline` trace reads like a glossary of your codebase's vocabulary: every function name, every argument name, laid bare. If the naming feels incoherent when you read the trace, it will feel incoherent to the next developer who reads the code.

### The "I wrote this six months ago" problem

Your own code becomes unfamiliar over time. CodeStory is a fast way to re-orient yourself in a part of the codebase you haven't touched in a while, without re-reading every function definition.

## What Makes CodeStory Different?

**It's not `IO.inspect`.** `IO.inspect` shows you one value at one point. CodeStory shows you the entire call flow at once — every function's inputs and outputs in a single structured trace. No more scattering inspect calls and piecing together interleaved output.

**It's not `dbg`.** Elixir's built-in `dbg/2` is great for pipeline debugging — seeing each step of a `|>` chain. But it operates on a single expression. CodeStory captures a _span_ of execution between tell and stop, showing every user-defined function call in that window. When a bug could be in any of a dozen functions in the call chain, CodeStory lets you see all of them at once.

**It's not a profiler.** Profilers care about timing and performance. CodeStory cares about comprehension — what called what, with what data, and what came back.

**It filters the noise.** Erlang's tracing tools capture everything: standard library calls, compiler-generated functions, dependency internals. CodeStory automatically filters all of that out, showing only your project's own code. You see the signal, not the noise.

**It names things.** Most tracing tools show you argument positions. CodeStory reads the actual parameter names from your compiled BEAM files — scanning across all function clauses to find the best name for each position — and displays them alongside values. Instead of `add(3, 2)`, you see `widgets_requested: 3, price_per_unit: 2`.

## How It Works (The Short Version)

1. CodeStory reads your `mix.exs` to figure out which modules belong to your project
2. It sets up Erlang's built-in tracing (only on the current process — safe and lightweight)
3. A collector process catches every function call and return, building a nested tree
4. When you call `stop()` (or the traced function returns), the tree is rendered as formatted, color-coded output

No macros. No special syntax. No compile-time hooks. Just `CodeStory.tell()` and `CodeStory.stop()`.

## Designed for Real Codebases

CodeStory was built with practical, everyday use in mind:

- **Module names in the trace** — Every function call shows its full module path, so you can immediately see when execution crosses module boundaries. This makes it easy to spot unexpected coupling or verify that your contexts stay clean.

- **Dev-only by design** — Install it with `only: :dev` and any `CodeStory.tell()` call accidentally left in your code will fail to compile in production. It's a guardrail, not a footgun.

- **Three levels of detail** — `:outline` for the shape of the call flow, `:short_story` for a readable trace with truncated values, `:novel` for the complete unabridged picture. Start with the outline, zoom in where it matters.

- **File output** — Send traces to `code_story_trace.log` for sharing with teammates, attaching to pull requests, or comparing before-and-after call flows during a refactor.

- **Zero configuration** — No config files, no setup steps, no module annotations. It works the moment you add the dependency.

## Who Is CodeStory For?

- **Developers joining a new team** who need to hear how the code works, fast
- **Anyone tracking down a bug** who wants to see every function's inputs and outputs in one place instead of scattering `IO.inspect` calls
- **Senior engineers refactoring** who want runtime proof of what a code path actually does before changing it
- **Team leads reviewing architecture** who want to see if module boundaries are being respected in practice
- **Anyone working in Elixir** who has ever thought "I wish I could just _hear_ what this code does"

## Getting Started

Add CodeStory to your `mix.exs`:

```elixir
defp deps do
  [{:code_story, github: "angeleahdaidone/code_story", only: :dev}]
end
```

Run `mix deps.get`, then drop `CodeStory.tell()` and `CodeStory.stop()` around any code you want to understand. That's it. No configuration, no setup, no ceremony.

See the [README](README.md) for the full API reference and options.
