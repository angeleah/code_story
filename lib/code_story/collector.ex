defmodule CodeStory.Collector do
  @moduledoc """
  GenServer that receives trace events and builds a nested call tree.

  Started with `GenServer.start/2` (not `start_link`) so that a crash
  does not kill the user's calling process.
  """

  use GenServer

  defstruct [:caller_pid, :args_map, :opts, :status, tree: [], stack: []]

  ## Public API

  def start(caller_pid, args_map, opts) do
    GenServer.start(__MODULE__, {caller_pid, args_map, opts})
  end

  ## Callbacks

  @impl true
  def init({caller_pid, args_map, opts}) do
    Process.monitor(caller_pid)

    {:ok,
     %__MODULE__{
       caller_pid: caller_pid,
       args_map: args_map,
       opts: opts,
       status: :tracing,
       tree: [],
       stack: []
     }}
  end

  @impl true
  def handle_cast({:trace_event, _event}, %{status: {:completed, _}} = state) do
    # Ignore events after auto-stop
    {:noreply, state}
  end

  def handle_cast({:trace_event, {:call, {mod, fun, args}}}, state) do
    if dunder?(fun) do
      {:noreply, %{state | stack: [:skip_dunder | state.stack]}}
    else
      named_args = enrich_args(mod, fun, args, state.args_map)

      node = %{
        module: mod,
        function: fun,
        args: named_args,
        return: nil,
        children: []
      }

      {:noreply, %{state | stack: [node | state.stack]}}
    end
  end

  def handle_cast({:trace_event, {:return_from, {_mod, _fun, _arity}, return_value}}, state) do
    case state.stack do
      [] ->
        {:noreply, state}

      [:skip_dunder | rest] ->
        {:noreply, %{state | stack: rest}}

      [current | rest] ->
        completed = %{current | return: return_value}

        case rest do
          [] ->
            # Stack empty — auto-stop
            new_tree = state.tree ++ [completed]
            {:noreply, %{state | tree: new_tree, stack: [], status: {:completed, new_tree}}}

          [parent | grandparents] ->
            parent = %{parent | children: parent.children ++ [completed]}
            {:noreply, %{state | stack: [parent | grandparents]}}
        end
    end
  end

  @impl true
  def handle_call(:get_result, _from, state) do
    case state.status do
      {:completed, tree} ->
        {:reply, {:completed, tree, state.opts}, state}

      :tracing ->
        {:reply, {:tracing, state.tree, state.opts}, state}
    end
  end

  # Raw trace messages from :trace session (OTP 28+)
  # The Collector pid is set as the tracer, so messages arrive here directly
  @impl true
  def handle_info({:trace, _pid, :call, {mod, fun, args}}, state) do
    handle_cast({:trace_event, {:call, {mod, fun, args}}}, state)
  end

  def handle_info({:trace, _pid, :return_from, {mod, fun, arity}, return_value}, state) do
    handle_cast({:trace_event, {:return_from, {mod, fun, arity}, return_value}}, state)
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{caller_pid: pid} = state) do
    {:stop, :normal, state}
  end

  # Ignore other trace messages (e.g. :trace_ts variants)
  def handle_info({:trace, _pid, _type, _info}, state), do: {:noreply, state}
  def handle_info({:trace, _pid, _type, _info, _extra}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  ## Private

  defp enrich_args(mod, fun, args, args_map) do
    arity = length(args)

    names =
      case Map.fetch(args_map, {mod, fun, arity}) do
        {:ok, names} -> names
        :error -> Enum.map(1..max(arity, 1)//1, &:"arg#{&1}") |> Enum.take(arity)
      end

    Enum.zip(names, args)
  end

  defp dunder?(fun) do
    name = Atom.to_string(fun)
    String.starts_with?(name, "__") and String.ends_with?(name, "__")
  end
end
