defmodule CodeStory.NoRawInspectTest do
  use ExUnit.Case, async: true

  # Guard: every value inspection in the formatter and encoder must route through the
  # `CodeStory.CleanInspect` chokepoint (via `do_inspect/2` / `inspect_value/2`), so
  # Ecto `__meta__`/`NotLoaded` noise can never leak from a newly-added site (this is
  # the check that would have caught the missed site-127 leak).
  @files ~w(lib/code_story/formatter.ex lib/code_story/encoder.ex)

  # Every forbidden form of a value inspect. The sanctioned routes —
  # `CodeStory.CleanInspect.inspect(`, `do_inspect(`, `inspect_value(` — are all left
  # unmatched, so only a real bypass trips the guard.
  #
  #   * bare `inspect(`      — the house idiom for an un-wrapped call. The `(?<![\w.])`
  #                            lookbehind skips `do_inspect(`/`.inspect(`/`inspect_x`.
  #   * `Kernel.inspect(`    — dotted bypasses the bare check's lookbehind lets through,
  #   * `IO.inspect(`          each of which would skip CleanInspect and leak Ecto noise.
  @forbidden [
    {~r/(?<![\w.])inspect\(/, "an un-wrapped `inspect(`"},
    {~r/\bKernel\.inspect\(/, "a `Kernel.inspect(` bypass"},
    {~r/\bIO\.inspect\(/, "an `IO.inspect(` bypass"}
  ]

  test "no un-wrapped value-inspect/2 in the formatter or encoder" do
    for file <- @files, {pattern, label} <- @forbidden do
      src = File.read!(file)

      assert Regex.scan(pattern, src) == [],
             "#{file} contains #{label} — route it through CodeStory.CleanInspect " <>
               "(e.g. `do_inspect/2`) so Ecto `__meta__`/`NotLoaded` noise is stripped."
    end
  end

  # Negative control: prove each pattern actually discriminates a real bypass from the
  # sanctioned routes — otherwise a botched lookbehind could silently make the guard
  # above pass vacuously on clean source and stop protecting anything.
  test "each guard pattern fires on a known bypass and stays quiet on sanctioned routes" do
    bypasses = ["x = inspect(v, o)", "x = Kernel.inspect(v, o)", "IO.inspect(v)"]

    sanctioned = [
      "do_inspect(v, o)",
      "inspect_value(v, d)",
      "CodeStory.CleanInspect.inspect(v, o)"
    ]

    for {pattern, label} <- @forbidden do
      assert Enum.any?(bypasses, &(Regex.scan(pattern, &1) != [])),
             "guard pattern for #{label} matched no known bypass — it may be silently broken."

      for ok <- sanctioned do
        assert Regex.scan(pattern, ok) == [],
               "guard pattern for #{label} false-flagged the sanctioned route `#{ok}`."
      end
    end
  end
end
