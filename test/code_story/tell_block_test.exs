defmodule CodeStory.TellBlockTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CodeStory.TestSupport.SampleApp

  setup do
    on_exit(fn ->
      CodeStory.Tracer.stop_tracing()

      case Process.get(:code_story_collector) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid)
      end

      Process.delete(:code_story_collector)
      File.rm_rf("code_story_trace.log")
    end)

    :ok
  end

  describe "tell/2 block form — returns result, prints trace, no stop()" do
    test "returns the fn's result and prints the trace" do
      {result, output} =
        with_io(fn -> CodeStory.tell(fn -> SampleApp.add_sub_mult(3, 2) end) end)

      assert result == 20
      assert output =~ "CodeStory Trace"
      assert output =~ "add_sub_mult"
    end

    test "needs no stop/0 — leaves no active trace, and tell()/stop() work after" do
      capture_io(fn -> CodeStory.tell(fn -> SampleApp.add(1, 2) end) end)
      assert Process.get(:code_story_collector) == nil

      assert :ok = CodeStory.tell()
      capture_io(fn -> CodeStory.stop() end)
    end

    test "no-traced-calls fun returns its value and prints nothing" do
      {result, output} = with_io(fn -> CodeStory.tell(fn -> :bare end) end)
      assert result == :bare
      refute output =~ "CodeStory Trace"
    end
  end

  describe "tell/2 block form — honors display opts" do
    test "detail: :outline drops returns; output: :file writes the log" do
      out =
        capture_io(fn ->
          CodeStory.tell(fn -> SampleApp.add_sub_mult(3, 2) end, detail: :outline)
        end)

      refute out =~ "=>"

      capture_io(fn -> CodeStory.tell(fn -> SampleApp.add(1, 2) end, output: :file) end)
      assert File.exists?("code_story_trace.log")
    end

    test "fold and depth apply through the block path" do
      folded = capture_io(fn -> CodeStory.tell(fn -> SampleApp.repeat_add(2) end) end)
      assert folded =~ "×3"

      capped =
        capture_io(fn -> CodeStory.tell(fn -> SampleApp.add_sub_mult(3, 2) end, depth: 1) end)

      assert capped =~ "more level"
    end
  end

  describe "tell/2 block form — never breaks wrapped code" do
    test "already-active trace: warns honestly, runs fun, returns result" do
      :ok = CodeStory.tell()

      {result, warn} =
        with_io(:stderr, fn -> CodeStory.tell(fn -> SampleApp.add(1, 2) end) end)

      assert result == 3
      assert warn =~ "may not be captured"

      capture_io(fn -> CodeStory.stop() end)
    end

    test "display/write failure: still returns the fn result, warns, does not raise" do
      # A directory at the log path makes File.write!/2 fail deterministically.
      File.rm_rf!("code_story_trace.log")
      File.mkdir_p!("code_story_trace.log")

      {result, warn} =
        with_io(:stderr, fn -> CodeStory.tell(fn -> SampleApp.add(2, 2) end, output: :file) end)

      assert result == 4
      assert warn =~ "could not be displayed"

      File.rm_rf!("code_story_trace.log")
    end

    test "a raised fun re-raises and leaves no active trace" do
      assert_raise RuntimeError, "boom", fn ->
        CodeStory.tell(fn -> raise "boom" end)
      end

      assert Process.get(:code_story_collector) == nil
    end
  end

  describe "safe_start/2 totalization" do
    test "every failure shape collapses to {:could_not_start, _} without raising" do
      assert {:could_not_start, {:error, :nope}} =
               CodeStory.safe_start([], fn _ -> {:error, :nope} end)

      assert {:could_not_start, %RuntimeError{}} = CodeStory.safe_start([], fn _ -> raise "x" end)
      assert {:could_not_start, :boom} = CodeStory.safe_start([], fn _ -> exit(:boom) end)
      assert {:could_not_start, :t} = CodeStory.safe_start([], fn _ -> throw(:t) end)
    end

    test "a clean start passes through as :ok" do
      assert :ok = CodeStory.safe_start([], fn _ -> :ok end)
    end
  end

  describe "tell dispatch — guard-rails & regression" do
    test "manual forms still start a trace (regression)" do
      assert :ok = CodeStory.tell([])
      capture_io(fn -> CodeStory.stop() end)

      assert :ok = CodeStory.tell(detail: :novel)
      capture_io(fn -> CodeStory.stop() end)
    end

    test "invalid args raise a friendly ArgumentError, not FunctionClauseError" do
      assert_raise ArgumentError, fn -> CodeStory.tell(&Kernel.abs/1) end
      assert_raise ArgumentError, fn -> CodeStory.tell(:atom) end
      assert_raise ArgumentError, fn -> CodeStory.tell(%{}) end
    end

    test "arity-2 error message names the wrong argument correctly" do
      # bad first arg → names the function
      bad_fun = assert_raise ArgumentError, fn -> CodeStory.tell(:x, []) end
      assert Exception.message(bad_fun) =~ "0-arity function"

      # valid fun, bad opts → names opts (not the fun)
      bad_opts = assert_raise ArgumentError, fn -> CodeStory.tell(fn -> :x end, :nope) end
      assert Exception.message(bad_opts) =~ "keyword list as the second argument"
    end

    test "narrate/2 still raises on an active trace (documented asymmetry)" do
      :ok = CodeStory.tell()
      assert_raise ArgumentError, fn -> CodeStory.narrate(fn -> SampleApp.add(1, 1) end) end
      capture_io(fn -> CodeStory.stop() end)
    end
  end
end
