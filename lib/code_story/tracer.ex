defmodule CodeStory.Tracer do
  @moduledoc """
  Configures Erlang tracing to feed events into the Collector.

  Uses OTP 28's `:trace` module with session-based tracing.
  The Collector pid is set as the tracer — trace messages arrive
  directly as `handle_info` callbacks.
  """

  @doc """
  Starts tracing the given process for calls to the given modules.

  The `collector_pid` receives trace messages directly.
  Returns `:ok` or `{:error, reason}`.
  """
  def start_tracing(collector_pid, modules, traced_pid) do
    try do
      # Use a unique session name to avoid conflicts
      session_name = :"code_story_trace_#{:erlang.unique_integer([:positive])}"
      session = :trace.session_create(session_name, collector_pid, [])

      :trace.process(session, traced_pid, true, [:call])

      match_spec = [{:_, [], [{:return_trace}]}]

      Enum.each(modules, fn module ->
        # OTP 28's :trace.function doesn't support wildcards for function/arity
        # Enumerate all functions and set trace patterns explicitly.
        # module_info(:functions) includes private (defp) functions, unlike
        # __info__(:functions) which lists only public ones. Compiler-generated
        # entries (anonymous funs, "-name/arity-fun-0-") are excluded.
        functions =
          module.module_info(:functions)
          |> Enum.reject(fn {fun, _arity} ->
            fun |> Atom.to_string() |> String.starts_with?("-")
          end)

        Enum.each(functions, fn {fun, arity} ->
          :trace.function(session, {module, fun, arity}, match_spec, [:local])
        end)
      end)

      # Store session for cleanup
      Process.put(:code_story_trace_session, session)
      :ok
    rescue
      e in ArgumentError ->
        {:error, "Failed to start tracing: #{Exception.message(e)}"}
    end
  end

  @doc """
  Stops tracing and cleans up. Idempotent — safe to call multiple times.
  """
  def stop_tracing do
    case Process.get(:code_story_trace_session) do
      nil ->
        :ok

      session ->
        try do
          :trace.session_destroy(session)
        rescue
          ArgumentError -> :ok
        end

        Process.delete(:code_story_trace_session)
        :ok
    end
  end
end
