defmodule CodeStory.CleanInspectTest do
  use ExUnit.Case, async: true

  alias CodeStory.CleanInspect
  alias CodeStory.TestSupport.{EctoIsh, EctoIshAssoc, FakeMeta, FakeNotLoaded}

  describe "strip_ecto_noise/1" do
    test "strips a first-position __meta__" do
      assert CleanInspect.strip_ecto_noise(
               ~s(%O{__meta__: #Ecto.Schema.Metadata<:loaded, "orders">, id: 12})
             ) == ~s(%O{id: 12})
    end

    test "strips a last-position __meta__ (safety net)" do
      assert CleanInspect.strip_ecto_noise(
               ~s(%O{id: 12, __meta__: #Ecto.Schema.Metadata<:loaded, "orders">})
             ) == ~s(%O{id: 12})
    end

    test "drops a NotLoaded association field" do
      assert CleanInspect.strip_ecto_noise(
               ~s(%O{id: 12, event: #Ecto.Association.NotLoaded<association :event is not loaded>, status: "paid"})
             ) == ~s(%O{id: 12, status: "paid"})
    end

    test "cleans multiple / nested occurrences" do
      s =
        ~s(%O{__meta__: #Ecto.Schema.Metadata<:loaded, "orders">, id: 1, ) <>
          ~s(user: %U{__meta__: #Ecto.Schema.Metadata<:loaded, "users">, name: "x"}, ) <>
          ~s(event: #Ecto.Association.NotLoaded<association :event is not loaded>})

      out = CleanInspect.strip_ecto_noise(s)
      refute out =~ "Ecto.Schema.Metadata"
      refute out =~ "Ecto.Association.NotLoaded"
      assert out =~ "%O{id: 1"
      assert out =~ ~s(%U{name: "x"})
    end

    test "is idempotent" do
      s = ~s(%O{__meta__: #Ecto.Schema.Metadata<:loaded, "orders">, id: 12})
      once = CleanInspect.strip_ecto_noise(s)
      assert CleanInspect.strip_ecto_noise(once) == once
    end
  end

  describe "inspect/2" do
    test "non-Ecto values inspect identically to Kernel.inspect" do
      for v <- [:ok, 42, "hi", %{a: 1, b: 2}, [1, 2, 3], {:a, :b}] do
        assert CleanInspect.inspect(v, limit: 3) == Kernel.inspect(v, limit: 3)
      end
    end

    test "a plain map with a __meta__ key is NOT bumped (no Ecto metadata to strip)" do
      # The limit bump must key off a rendered `#Ecto.Schema.Metadata<…>` marker, not a
      # bare `__meta__` key — otherwise this map would show `limit + 1` fields.
      v = %{__meta__: :whatever, a: 1, b: 2, c: 3, d: 4}
      assert CleanInspect.inspect(v, limit: 3) == Kernel.inspect(v, limit: 3)
    end

    test "strips __meta__ from a real struct value while keeping the %Mod{} name" do
      v = %EctoIsh{
        __meta__: %FakeMeta{state: :loaded, source: "fakes"},
        id: 1,
        status: "paid",
        kind: "individual"
      }

      out = CleanInspect.inspect(v, limit: :infinity)

      refute out =~ "Ecto.Schema.Metadata"
      assert out =~ "CodeStory.TestSupport.EctoIsh"
      assert out =~ "id: 1"
    end

    test "bump_limit_for_meta: a compact limit still shows the intended real-field count" do
      v = %EctoIsh{
        __meta__: %FakeMeta{state: :loaded, source: "fakes"},
        id: 1,
        status: "paid",
        kind: "individual"
      }

      # Struct fields inspect in DEFSTRUCT order: __meta__, id, status, kind. Without
      # the bump, limit:3 shows __meta__, id, status → after stripping __meta__,
      # `kind` is hidden.
      naive = v |> Kernel.inspect(limit: 3) |> CleanInspect.strip_ecto_noise()
      refute naive =~ "kind:"

      # With the bump (limit -> 4), kind survives.
      assert CleanInspect.inspect(v, limit: 3) =~ "kind:"
    end

    test "strips a NotLoaded association through the full inspect pipeline" do
      # End-to-end (not a hand-written string): the Inspect protocol renders the
      # `#Ecto.Association.NotLoaded<…>` bytes, then `inspect/2` must strip them while
      # keeping the struct name and the loaded fields.
      v = %EctoIshAssoc{
        __meta__: %FakeMeta{state: :loaded, source: "orders"},
        id: 7,
        event: %FakeNotLoaded{assoc: :event},
        status: "paid"
      }

      out = CleanInspect.inspect(v, limit: :infinity)

      refute out =~ "Ecto.Association.NotLoaded"
      refute out =~ "Ecto.Schema.Metadata"
      assert out =~ "CodeStory.TestSupport.EctoIshAssoc"
      assert out =~ "id: 7"
      assert out =~ ~s(status: "paid")
    end

    test "bump leaves :infinity and no-limit opts alone" do
      v = %EctoIsh{
        __meta__: %FakeMeta{state: :loaded, source: "fakes"},
        id: 1,
        status: "paid",
        kind: "individual"
      }

      # :infinity → all fields either way; just assert no crash + noise gone
      refute CleanInspect.inspect(v, limit: :infinity) =~ "Ecto.Schema.Metadata"
      refute CleanInspect.inspect(v, []) =~ "Ecto.Schema.Metadata"
    end
  end
end
