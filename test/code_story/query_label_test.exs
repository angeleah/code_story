defmodule CodeStory.QueryLabelTest do
  use ExUnit.Case, async: true

  alias CodeStory.QueryLabel

  # Hand-built maps that mimic the verified Ecto.Query shape without loading Ecto:
  # %Ecto.Query{from: %Ecto.Query.FromExpr{source: ...}}. `match?(%{__struct__: Ecto.Query})`
  # fires on a plain map with that key, so detection works with no dependency.
  defp query(source), do: %{__struct__: Ecto.Query, from: %{source: source}}

  describe "label/1 — source classes" do
    test "schema source renders the full module path, framed" do
      q = query({"regs", CodeStory.TestSupport.EctoIsh})
      assert QueryLabel.label(q) == "#Ecto.Query<CodeStory.TestSupport.EctoIsh>"
    end

    test "string-table source renders the quoted table, framed" do
      q = query({"registrations", nil})
      assert QueryLabel.label(q) == ~s(#Ecto.Query<"registrations">)
    end

    test "subquery source renders <subquery>" do
      q = query(%{__struct__: Ecto.SubQuery})
      assert QueryLabel.label(q) == "#Ecto.Query<subquery>"
    end

    test "unrecognized source shape renders the generic marker" do
      q = query(:weird)
      assert QueryLabel.label(q) == "#Ecto.Query<...>"
    end

    test "a query with from: nil (no source) renders the generic marker" do
      assert QueryLabel.label(%{__struct__: Ecto.Query, from: nil}) == "#Ecto.Query<...>"
      assert QueryLabel.label(%{__struct__: Ecto.Query}) == "#Ecto.Query<...>"
    end
  end

  describe "label/1 — non-queries fall through to nil" do
    test "ordinary values return nil" do
      for v <- [:ok, 42, "hi", %{a: 1}, [1, 2, 3], {:a, :b}, nil] do
        assert QueryLabel.label(v) == nil
      end
    end

    test "a real (non-query) struct returns nil" do
      assert QueryLabel.label(%CodeStory.TestSupport.EctoIsh{id: 1}) == nil
    end

    test "match is crash-safe on exotic terms" do
      for v <- [self(), &QueryLabel.label/1, [1 | 2]] do
        assert QueryLabel.label(v) == nil
      end
    end
  end
end
