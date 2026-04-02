defmodule CodeStory.IntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CodeStory.TestSupport.SampleApp

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

      File.rm("code_story_trace.log")
    end)

    :ok
  end

  # Helper: run traced function in a spawned process, output to file, return file content
  defp traced_run_to_file(fun, opts \\ []) do
    test_pid = self()
    opts = Keyword.merge([output: :file], opts)

    spawn(fn ->
      CodeStory.tell(opts)
      result = fun.()
      CodeStory.stop()
      send(test_pid, {:done, result})
    end)

    assert_receive {:done, _result}, 2000
    Process.sleep(100)

    if File.exists?("code_story_trace.log") do
      File.read!("code_story_trace.log")
    else
      ""
    end
  end

  describe "end-to-end tracing" do
    test "traces nested function calls" do
      content = traced_run_to_file(fn -> SampleApp.add_sub_mult(3, 2) end)

      assert content =~ "CodeStory Trace"
      assert content =~ "add_sub_mult"
      assert content =~ "add"
      assert content =~ "subtract"
      assert content =~ "mult"
      assert content =~ "=> CodeStory.TestSupport.SampleApp.add_sub_mult returned 20"
      assert content =~ "End Trace"
    end

    test "show_args: false shows values only" do
      content = traced_run_to_file(fn -> SampleApp.add(3, 2) end, show_args: false)

      assert content =~ "add\n"
      assert content =~ "  3\n"
      refute content =~ "num1:"
    end

    test "show_args: true shows arg names" do
      content = traced_run_to_file(fn -> SampleApp.add(3, 2) end, show_args: true)

      assert content =~ "num1:"
      assert content =~ "num2:"
    end

    test "detail: :novel shows complete values without truncation" do
      big_map = %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5, "f" => 6, "g" => 7}
      content = traced_run_to_file(fn -> SampleApp.process_data(big_map) end, detail: :novel)

      # In :novel mode, all keys should be present
      assert content =~ "\"g\" => 7"
    end

    test "detail: :short_story truncates large values" do
      big_map = %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5, "f" => 6, "g" => 7}

      content =
        traced_run_to_file(fn -> SampleApp.process_data(big_map) end, detail: :short_story)

      # In :short_story mode, should be truncated
      assert content =~ "..."
      refute content =~ "\"g\" => 7"
    end

    test "traces functions with sub-calls" do
      content = traced_run_to_file(fn -> SampleApp.do_stuff(10, 3) end)

      assert content =~ "do_stuff"
      assert content =~ "divide"
      assert content =~ "hello 3"
    end

    test "traces recursive functions" do
      content = traced_run_to_file(fn -> SampleApp.recursive_countdown(3) end)

      assert content =~ "recursive_countdown"
      assert content =~ ":done"
    end

    test "file output has no ANSI codes" do
      content = traced_run_to_file(fn -> SampleApp.add(1, 2) end)

      refute content =~ "\e["
    end
  end

  describe "edge cases" do
    test "double stop does not crash" do
      test_pid = self()

      output =
        capture_io(:stderr, fn ->
          gl = Process.group_leader()

          spawn(fn ->
            Process.group_leader(self(), gl)
            CodeStory.tell()
            SampleApp.add(1, 2)
            CodeStory.stop()
            CodeStory.stop()
            send(test_pid, :done)
          end)

          assert_receive :done, 2000
          Process.sleep(50)
        end)

      assert output =~ "no active trace"
    end

    test "stop without start warns gracefully" do
      output =
        capture_io(:stderr, fn ->
          CodeStory.stop()
        end)

      assert output =~ "no active trace"
    end

    test "multiple start calls returns error" do
      test_pid = self()

      spawn(fn ->
        CodeStory.tell()
        result = CodeStory.tell()
        send(test_pid, {:result, result})
        CodeStory.stop()
      end)

      assert_receive {:result, {:error, :already_tracing}}, 2000
    end
  end
end
