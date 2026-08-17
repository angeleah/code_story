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
    * `:output` - `:terminal` (default), `:file`, or `:both`. `:file` and
      `:both` write to `code_story_trace.log` in the project root. Because a
      trace records real argument and return values, that file can capture
      secrets (passwords, API keys, tokens) or personal data in plaintext —
      add it to your `.gitignore` and delete it when you are done with it.
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

  Pair with `stop/0`, which prints the collected call tree:

      CodeStory.tell()
      result = process_order(params)
      CodeStory.stop()

  Accepts the options documented in the [module docs](`CodeStory`) —
  `:show_args`, `:output`, `:detail`, `:auto_boundary`, `:fold_repeats`, and
  `:depth`. For example:

      CodeStory.tell(detail: :outline)
      CodeStory.tell(detail: :novel, output: :file)

  Returns `:ok`, or `{:error, :already_tracing}` (with a warning) if a trace is
  already active on this process. For a non-printing, data-returning
  alternative, see `narrate/2`.
  """
  @spec tell(keyword()) :: :ok | {:error, term()}
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
  Stops tracing and outputs the call tree collected since `tell/1`.

  The entire trace is written as one buffered block, using the `:output` and
  `:detail` options given to `tell/1` — so the tree never interleaves with other
  IO from your code.

  Always returns `:ok`. Warns and returns `:ok` if no trace is active on this
  process, so a stray `stop/0` is harmless.
  """
  @spec stop() :: :ok
  def stop do
    case Process.get(@collector_key) do
      nil ->
        IO.warn("CodeStory: no active trace")
        :ok

      collector_pid ->
        do_stop(collector_pid)
    end
  end

  @doc """
  Runs `fun` while tracing, returning `{result, tree}` without printing.

  `result` is whatever `fun` returned; `tree` is the raw call tree as data — a
  list of `%{module, function, args, return, children}` node maps. This is the
  programmatic counterpart to `tell/0` + `stop/0`: nothing is written to the
  terminal or a file, and no display transforms (folding, depth) are applied — the
  tree is the honest, full structure. Pair it with `to_encodable/2` to get
  JSON-ready data.

      {invoice, tree} = CodeStory.narrate(fn -> process_order(params) end)

  Notes:

    * Traces the calling process and captures only the **first** top-level call, so
      the clean pattern is one entry call: `narrate(fn -> entry(...) end)`. A `fun`
      with no traced calls returns `{result, []}`.
    * `opts` are trace-time only — currently `:auto_boundary` (default `true`, as in
      `tell/1`). Pass `auto_boundary: false` to include an Ecto repo's internals in
      the raw tree.
    * **Raises** `ArgumentError` if a trace is already active on this process
      (unlike `tell/1`, which returns `{:error, :already_tracing}` — a tagged tuple
      would be ambiguous with a legitimate `{:error, tree}` result).
  """
  @spec narrate((-> result), keyword()) :: {result, [map()]} when result: var
  def narrate(fun, opts \\ []) when is_function(fun, 0) do
    if Process.get(@collector_key) do
      raise ArgumentError, "CodeStory.narrate: a trace is already active on this process"
    end

    opts = Keyword.merge([auto_boundary: true], opts)

    case do_start(opts) do
      :ok ->
        # do_start put the collector pid under @collector_key before returning :ok.
        collector_pid = Process.get(@collector_key)

        try do
          result = fun.()
          {result, fetch_tree(collector_pid)}
        after
          CodeStory.Tracer.stop_tracing()
          Process.delete(@collector_key)
          # Benign TOCTOU: the collector only dies if its monitored caller (this
          # process) dies, which cannot happen mid-cleanup here.
          if is_pid(collector_pid) and Process.alive?(collector_pid) do
            GenServer.stop(collector_pid)
          end
        end

      {:error, reason} ->
        raise "CodeStory.narrate: could not start tracing (#{inspect(reason)})"
    end
  end

  @doc """
  Converts a call tree (from `narrate/2`) into a JSON-ready plain-data structure.

  Dependency-free: the result contains only strings / numbers / booleans / nil /
  lists / maps, so `JSON.encode!/1` (Elixir 1.18+) or `Jason.encode!/1` works
  directly. Faithful by default; opt into compaction with `:fold_repeats`,
  `:depth`, and `:detail`. See `CodeStory.Encoder` for the schema and options.

      {_result, tree} = CodeStory.narrate(fn -> entry() end)
      data = CodeStory.to_encodable(tree, fold_repeats: true, depth: 4)
  """
  @spec to_encodable([map()], keyword()) :: [map()]
  def to_encodable(tree, opts \\ []), do: CodeStory.Encoder.encode(tree, opts)

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

  # Trace events reach the collector asynchronously, and the collector only fills
  # `tree` at completion (nodes live on its stack until then) — so there is no
  # observable "partial tree", only `:tracing` vs `:completed`. Poll `:completed`.
  #
  # The catch: a still-draining large trace and a genuinely call-free `fun` both
  # look like `:tracing` with an empty tree. The collector's sticky `saw_call`
  # flag distinguishes them: once a call has arrived, we keep waiting (up to a
  # generous ceiling) for `:completed`; if no call has arrived past a short grace,
  # the `fun` made no traced calls and we return `[]`.
  @saw_call_grace_ms 50
  @completion_ceiling_ms 5_000

  defp fetch_tree(pid), do: fetch_tree(pid, 0)

  defp fetch_tree(pid, waited) do
    case GenServer.call(pid, :trace_progress) do
      {:completed, tree} ->
        tree

      # No call ever observed past the grace window → the fun made no traced calls.
      {:tracing, false} when waited >= @saw_call_grace_ms ->
        []

      # A call arrived but completion is taking unusually long → give up safely.
      {:tracing, _saw_call} when waited >= @completion_ceiling_ms ->
        []

      {:tracing, _saw_call} ->
        Process.sleep(2)
        fetch_tree(pid, waited + 2)
    end
  catch
    :exit, {:noproc, _} -> []
    :exit, {:normal, _} -> []
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
