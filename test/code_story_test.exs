defmodule CodeStoryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    on_exit(fn ->
      CodeStory.Tracer.stop_tracing()

      case Process.get(:code_story_collector) do
        nil ->
          :ok

        pid ->
          if Process.alive?(pid), do: GenServer.stop(pid)
          Process.delete(:code_story_collector)
      end
    end)

    :ok
  end

  describe "start/1" do
    test "returns :ok on success" do
      assert :ok = CodeStory.tell()
      CodeStory.stop()
    end

    test "warns when trace already active" do
      :ok = CodeStory.tell()

      output =
        capture_io(:stderr, fn ->
          result = CodeStory.tell()
          assert result == {:error, :already_tracing}
        end)

      assert output =~ "already active"
      CodeStory.stop()
    end

    test "accepts options" do
      assert :ok = CodeStory.tell(show_args: false, output: :file)
      CodeStory.stop()
    end
  end

  describe "stop/0" do
    test "warns when no active trace" do
      output =
        capture_io(:stderr, fn ->
          CodeStory.stop()
        end)

      assert output =~ "no active trace"
    end

    test "double stop does not crash" do
      :ok = CodeStory.tell()
      CodeStory.stop()

      output =
        capture_io(:stderr, fn ->
          CodeStory.stop()
        end)

      assert output =~ "no active trace"
    end
  end
end
