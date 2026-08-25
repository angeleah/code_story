defmodule CodeStory.EncoderTest do
  use ExUnit.Case, async: true

  alias CodeStory.Encoder

  defp node(mod, fun, args, ret, children \\ []) do
    %{module: mod, function: fun, args: args, return: ret, children: children}
  end

  # Recursively assert a term contains only JSON-native shapes.
  defp json_safe!(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: :ok

  defp json_safe!(v) when is_list(v), do: Enum.each(v, &json_safe!/1)

  defp json_safe!(v) when is_map(v) do
    Enum.each(v, fn {k, val} ->
      assert is_atom(k) or is_binary(k)
      json_safe!(val)
    end)
  end

  defp json_safe!(other), do: flunk("non-JSON-safe term: #{inspect(other)}")

  describe "encode/2 — node schema" do
    test "encodes module/function/arity/args/return as plain strings" do
      tree = [node(MyApp.Orders, :validate_item, [item: %{sku: "A1"}], :ok)]
      assert [enc] = Encoder.encode(tree)

      assert enc.module == "MyApp.Orders"
      assert enc.function == "validate_item"
      assert enc.arity == 1
      assert enc.args == [%{name: "item", value: inspect(%{sku: "A1"}, limit: :infinity)}]
      assert enc.return == ":ok"
      assert enc.children == []
    end

    test "args keep order and there is one entry per positional arg" do
      tree = [node(M, :f, [a: 1, b: 2, c: 3], :ok)]
      assert [%{args: args, arity: 3}] = Encoder.encode(tree)
      assert Enum.map(args, & &1.name) == ["a", "b", "c"]
    end
  end

  describe "encode/2 — JSON safety" do
    test "output is JSON-native and round-trips through JSON when available" do
      tree = [node(M, :f, [x: {:a, :tuple}], %MapSet{} |> MapSet.put(1), [node(M, :g, [], :y)])]
      enc = Encoder.encode(tree)
      json_safe!(enc)

      if Code.ensure_loaded?(JSON) do
        assert is_binary(apply(JSON, :encode!, [enc]))
      end
    end

    test "empty tree encodes to empty list" do
      assert Encoder.encode([]) == []
    end
  end

  describe "encode/2 — faithful by default" do
    test "no count/varies/truncated and full (novel) values by default" do
      long = String.duplicate("x", 500)
      tree = [node(M, :f, [s: long], :ok, [node(M, :g, [], :y)])]
      assert [enc] = Encoder.encode(tree)

      refute Map.has_key?(enc, :count)
      refute Map.has_key?(enc, :varies)
      refute Map.has_key?(enc, :truncated)
      assert [arg] = enc.args
      assert arg.value =~ long
    end
  end

  describe "encode/2 — fold_repeats" do
    test "identical siblings fold to one node with count" do
      n = node(M, :f, [a: 1], :ok)
      assert [enc] = Encoder.encode([n, n, n], fold_repeats: true)
      assert enc.count == 3
      refute Map.has_key?(enc, :varies)
    end

    test "varying siblings fold to count + varies" do
      run = [node(M, :f, [a: 1], :ok), node(M, :f, [a: 2], :ok)]
      assert [enc] = Encoder.encode(run, fold_repeats: true)
      assert enc.count == 2
      assert enc.varies == true
    end
  end

  describe "encode/2 — depth" do
    # A→B→C→D chain (4 levels).
    defp deep do
      [
        node(M, :a, [x: 1], :ra, [
          node(M, :b, [x: 2], :rb, [node(M, :c, [x: 3], :rc, [node(M, :d, [x: 4], :rd)])])
        ])
      ]
    end

    test "depth: 1 keeps only the root, empties children, marks truncated" do
      assert [enc] = Encoder.encode(deep(), depth: 1)
      assert enc.function == "a"
      assert enc.children == []
      assert enc.truncated == 3
    end

    test "depth: :infinity nests fully with no truncated field" do
      assert [a] = Encoder.encode(deep(), depth: :infinity)
      refute Map.has_key?(a, :truncated)
      assert [b] = a.children
      assert [c] = b.children
      assert [d] = c.children
      assert d.function == "d" and d.children == []
    end

    test "depth: 2 cuts under B with truncated == 2 (formatter agreement)" do
      assert [a] = Encoder.encode(deep(), depth: 2)
      assert [b] = a.children
      assert b.function == "b"
      assert b.children == []
      assert b.truncated == 2
    end

    test "depth: 3 cuts under C with truncated == 1" do
      assert [a] = Encoder.encode(deep(), depth: 3)
      assert [b] = a.children
      assert [c] = b.children
      assert c.function == "c"
      assert c.children == []
      assert c.truncated == 1
    end

    test "clamp: depth 0 == depth 1, and float 2.0 == 2" do
      assert Encoder.encode(deep(), depth: 0) == Encoder.encode(deep(), depth: 1)
      assert Encoder.encode(deep(), depth: 2.0) == Encoder.encode(deep(), depth: 2)
    end
  end

  describe "encode/2 — Ecto noise stripped from values" do
    alias CodeStory.TestSupport.{EctoIsh, FakeMeta}

    test "to_encodable strips __meta__ from an arg value and the return, keeps the name" do
      v = %EctoIsh{
        __meta__: %FakeMeta{state: :loaded, source: "orders"},
        id: 12,
        status: "paid",
        kind: "x"
      }

      tree = [node(M, :f, [order: v], v)]
      assert [enc] = Encoder.encode(tree)

      refute hd(enc.args).value =~ "Ecto.Schema.Metadata"
      refute enc.return =~ "Ecto.Schema.Metadata"
      assert enc.return =~ "EctoIsh"
    end
  end

  describe "encode/2 — boundary flag is dropped (whitelist)" do
    test "a :boundary node encodes identically to one without the flag" do
      with_flag = [Map.put(node(M, :f, [a: 1], :ok), :boundary, true)]
      without = [node(M, :f, [a: 1], :ok)]

      assert Encoder.encode(with_flag) == Encoder.encode(without)
      refute Enum.any?(Encoder.encode(with_flag), &Map.has_key?(&1, :boundary))
    end
  end

  describe "encode/2 — detail" do
    test ":short_story truncates long values; :novel does not" do
      long = String.duplicate("x", 500)
      tree = [node(M, :f, [s: long], :ok)]

      [short] = Encoder.encode(tree, detail: :short_story)
      [novel] = Encoder.encode(tree, detail: :novel)

      assert hd(short.args).value =~ "..."
      refute hd(novel.args).value =~ "..."
    end
  end
end
