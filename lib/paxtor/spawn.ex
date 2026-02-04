defmodule Paxtor.Spawn do
  @moduledoc """
  A via registry module for temporary singleton processes.
  """

  @doc """
  Returns a :via tuple that can be used to spawn or access the singleton
  process.
  """
  def via(key, child_spec) do
    {:via, __MODULE__, {key, child_spec}}
  end

  def alive?(key) do
    key
    |> lookup()
    |> is_pid()
  end

  def lookup(key) do
    case PaxosKV.get(key, bucket: __MODULE__, no_quorum: :retry) do
      {:ok, node} ->
        if node && Node.ping(node) == :pong do
          Paxtor.Sup.pid({Paxtor.Spawn.Supervisor, node}, key)
        else
          nil
        end

      {:error, :not_found} ->
        nil
    end
  catch
    _, _ -> nil
  end

  use Paxtor.RegistryBehaviour

  @impl Paxtor.RegistryBehaviour
  def whereis_name({key, child_spec}) do
    case start_child(key, child_spec) do
      {:ok, pid} when is_pid(pid) -> pid
      {:ok, pid, _info} when is_pid(pid) -> pid
      {:error, {:already_started, pid}} when is_pid(pid) -> pid
      no_pid_reponse -> throw({:no_pid, no_pid_reponse})
    end
  catch
    # :error, {:erpc, :noconnection} ->
    a, b ->
      IO.inspect([ERROR, a, b])
      lookup(key)
  end

  defp start_child(key, child_spec) do
    supervisor = {Paxtor.Spawn.Supervisor, chosen_node(key)}
    child_spec = normalized_child_spec(child_spec, key)
    Supervisor.start_child(supervisor, child_spec)
  end

  defp chosen_node(key) do
    node = Enum.random(PaxosKV.Cluster.nodes())

    case PaxosKV.put(key, node, node: node, bucket: __MODULE__, no_quorum: :return) do
      {:ok, node} -> node
      {:error, :invalid_value} -> chosen_node(key)
      {:error, :no_quorum} -> chosen_node(key)
    end
  end

  defp normalized_child_spec(child_spec, key) do
    Supervisor.child_spec(child_spec, id: key, restart: :temporary, significant: false)
  end
end
