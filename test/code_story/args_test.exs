defmodule CodeStory.ArgsTest do
  use ExUnit.Case, async: true

  describe "extract/1" do
    test "extracts parameter names for a module's functions" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])

      assert Map.has_key?(args_map, {CodeStory.TestSupport.SampleModule, :add, 2})
      assert args_map[{CodeStory.TestSupport.SampleModule, :add, 2}] == [:num1, :num2]
    end

    test "extracts single-arg functions" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      assert args_map[{CodeStory.TestSupport.SampleModule, :greet, 1}] == [:name]
    end

    test "extracts zero-arg functions" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      assert args_map[{CodeStory.TestSupport.SampleModule, :no_args, 0}] == []
    end

    test "uses first clause parameter names for multi-clause functions" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      # First clause is process(:ok, result)
      # :ok is a literal so falls back to positional, but result should be named
      names = args_map[{CodeStory.TestSupport.SampleModule, :process, 2}]
      assert is_list(names)
      assert length(names) == 2
      assert Enum.at(names, 1) == :result
    end

    test "extracts param names for functions with default args" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      # change(record, attrs \\ %{}) — arity-2 clause has real names
      assert args_map[{CodeStory.TestSupport.SampleModule, :change, 2}] == [:record, :attrs]
      # arity-1 is a generated wrapper — falls back to positional
      assert args_map[{CodeStory.TestSupport.SampleModule, :change, 1}] == [:arg1]
    end

    test "extracts param names from pattern-matched struct params" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      # transform(%{name: _} = record, opts) should give [:record, :opts]
      assert args_map[{CodeStory.TestSupport.SampleModule, :transform, 2}] == [:record, :opts]
    end

    test "extracts param names from struct pattern match like Phoenix contexts" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule])
      # update(%__MODULE__{} = record, attrs) should give [:record, :attrs]
      assert args_map[{CodeStory.TestSupport.SampleModule, :update, 2}] == [:record, :attrs]
    end

    test "handles multiple modules" do
      args_map = CodeStory.Args.extract([CodeStory.TestSupport.SampleModule, CodeStory.Modules])
      # Should have entries from both modules
      assert Map.has_key?(args_map, {CodeStory.TestSupport.SampleModule, :add, 2})
      assert Map.has_key?(args_map, {CodeStory.Modules, :camelize_app_name, 1})
    end

    test "returns empty map for empty module list" do
      assert CodeStory.Args.extract([]) == %{}
    end
  end
end
