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

  use Paxtor.RegistryBehaviour

  @impl Paxtor.RegistryBehaviour
  def whereis_name({key, child_spec}) do
    case start_child(key, child_spec) do
      {:ok, pid} when is_pid(pid) -> pid
      {:ok, pid, _info} when is_pid(pid) -> pid
      {:error, {:already_started, pid}} when is_pid(pid) -> pid
      no_pid_reponse -> throw({:no_pid, no_pid_reponse})
    end
  end

  defp start_child(key, child_spec) do
    supervisor = {Paxtor.RegistrySupervisor, chosen_node(key)}
    child_spec = normalized_child_spec(child_spec, key)
    Supervisor.start_child(supervisor, child_spec)
  end

  defp chosen_node(key) do
    node = Enum.random(PaxosKV.Cluster.nodes())
    {:ok, node} = PaxosKV.put(key, node, node: node, bucket: __MODULE__, no_quorum: :retry)
    node
  end

  defp normalized_child_spec(child_spec, key) do
    Supervisor.child_spec(child_spec, id: key, restart: :temporary, significant: false)
  end
end
