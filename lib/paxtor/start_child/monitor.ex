defmodule Paxtor.StartChild.Monitor do
  @moduledoc false

  use GenServer
  require PaxosKV.Helpers.Msg, as: Msg

  def start_link(key, custom_child_spec) do
    GenServer.start_link(__MODULE__, {key, custom_child_spec})
  end

  @impl true
  def init({key, custom_child_spec}) do
    {:ok, {key, custom_child_spec}, {:continue, :monitor_pid}}
  end

  @bucket __MODULE__ |> Module.split() |> List.delete_at(-1) |> Module.concat()
  @supervisor Module.concat(@bucket, Supervisor)

  @impl true
  def handle_continue(:monitor_pid, {key, custom_child_spec} = state) do
    node = Enum.random(PaxosKV.Cluster.nodes())
    my_node = Node.self()

    case PaxosKV.put(key, node, node: node, bucket: @bucket, no_quorum: :retry) do
      {:ok, ^my_node} ->
        {:stop, :shutdown, state}

      {:ok, node} when is_atom(node) ->
        Process.flag(:priority, :low)
        :erlang.yield()

        case Paxtor.Sup.pid({@supervisor, node}, key) do
          pid when is_pid(pid) ->
            Process.monitor(pid)
            Process.flag(:priority, :normal)
            {:noreply, {key, custom_child_spec, pid}, :hibernate}

          :undefined ->
            {:stop, :shutdown, state}

          _ ->
            Supervisor.start_child({@supervisor, node}, custom_child_spec)
            Process.sleep(100)
            handle_continue(:monitor_pid, state)
        end

      {:error, :invalid_value} ->
        handle_continue(:monitor_pid, state)
    end
  end

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :pong, state}

  @impl true
  def handle_info(
        Msg.monitor_down(ref: _, type: :process, pid: pid, reason: _),
        {key, custom_child_spec, pid}
      ) do
    {:noreply, {key, custom_child_spec}, {:continue, :monitor_pid}}
  end
end
