defmodule CodeStory do
  @moduledoc """
  A code comprehension tool for surveying unfamiliar Elixir code.

  Drop `CodeStory.tell()` into a function to see a nested call tree of
  user-defined function calls with named arguments, values, and return values.

  ## Usage

      CodeStory.tell()
      # ... your code ...
      CodeStory.stop()

  ## Options

    * `:show_args` - when `true` (default), shows argument names and values;
      when `false`, shows values only
    * `:output` - `:terminal` (default), `:file`, or `:both`
    * `:detail` - `:outline` shows only function names and arg names (no values
      or returns) for inspecting call flow and boundaries;
      `:short_story` (default) shows names, truncated values, and returns;
      `:novel` shows names with complete untruncated values and returns
    * `:auto_boundary` - when `true` (default), Ecto repos are treated as
      *boundary modules*: a repo call (e.g. `Repo.get!`) is shown as a single
      node with its args and return, but the repo's own internal calls (Ecto
      plumbing, arity-delegation chains) are hidden. Set to `false` to trace
      repo internals.
    * `:fold_repeats` - when `true` (default), consecutive sibling calls to the
      same function collapse into one node marked `×N` (or `×N (varies)` when the
      calls share a function but differ). Set to `false` to show every call.
    * `:depth` - caps how many levels the rendered trace nests. A positive
      integer (`depth: 1` shows the entry call only; `depth: 2` adds its direct
      children; etc.); below the cap a node's interior is replaced by a
      `… (N more levels)` marker. Defaults to `:infinity` (no limit).
  """

  @collector_key :code_story_collector

  @doc """
  Starts tracing user-defined function calls on the current process.
  """
  def tell(opts \\ []) do
    if Process.get(@collector_key) do
      IO.warn("CodeStory: trace already active on this process")
      {:error, :already_tracing}
    else
      opts =
        Keyword.merge(
          [
            show_args: true,
            output: :terminal,
            detail: :short_story,
            auto_boundary: true,
            fold_repeats: true,
            depth: :infinity
          ],
          opts
        )

      do_start(opts)
    end
  end

  @doc """
  Stops tracing and outputs the call tree.
  """
  def stop do
    case Process.get(@collector_key) do
      nil ->
        IO.warn("CodeStory: no active trace")
        :ok

      collector_pid ->
        do_stop(collector_pid)
    end
  end

  defp do_start(opts) do
    modules = CodeStory.Modules.detect()
    args_map = CodeStory.Args.extract(modules)

    # `tell/1` merges the `auto_boundary: true` default, so the value is always
    # present here — the default lives in exactly one place (the merge above).
    boundaries =
      if Keyword.get(opts, :auto_boundary) do
        CodeStory.Modules.ecto_repos(modules)
      else
        []
      end

    opts = Keyword.put(opts, :boundaries, boundaries)

    {:ok, collector_pid} = CodeStory.Collector.start(self(), args_map, opts)

    case CodeStory.Tracer.start_tracing(collector_pid, modules, self()) do
      :ok ->
        Process.put(@collector_key, collector_pid)
        :ok

      {:error, reason} ->
        GenServer.stop(collector_pid)
        {:error, reason}
    end
  end

  defp do_stop(collector_pid) do
    result =
      try do
        GenServer.call(collector_pid, :get_result)
      catch
        :exit, {:noproc, _} ->
          IO.warn("CodeStory: trace collector crashed — no output available")
          nil
      end

    CodeStory.Tracer.stop_tracing()
    Process.delete(@collector_key)

    case result do
      {:completed, tree, opts} ->
        output_result(tree, opts)

      {:tracing, _tree, opts} ->
        # Still tracing — get whatever tree we have
        tree =
          try do
            case GenServer.call(collector_pid, :get_result) do
              {:completed, tree, _} -> tree
              {:tracing, tree, _} -> tree
            end
          catch
            :exit, _ -> []
          end

        output_result(tree, opts)

      nil ->
        :ok
    end

    if Process.alive?(collector_pid), do: GenServer.stop(collector_pid)
    :ok
  end

  defp output_result(tree, _opts) when tree == [], do: :ok

  defp output_result(tree, opts) do
    tree = if Keyword.get(opts, :fold_repeats, true), do: CodeStory.Fold.fold(tree), else: tree
    output_mode = Keyword.get(opts, :output, :terminal)

    case output_mode do
      :terminal ->
        IO.puts(CodeStory.Formatter.format(tree, opts))

      :file ->
        write_file(tree, opts)

      :both ->
        IO.puts(CodeStory.Formatter.format(tree, opts))
        write_file(tree, opts)
    end
  end

  defp write_file(tree, opts) do
    content = CodeStory.Formatter.format_plain(tree, opts)
    path = Path.join(File.cwd!(), "code_story_trace.log")
    File.write!(path, content)
  end
end
