defmodule Paxtor.RegistrySupervisor do
  use Supervisor

  def start_link(args), do: Supervisor.start_link(__MODULE__, args, name: __MODULE__)

  @impl true
  def init(_), do: Supervisor.init([], strategy: :one_for_one)
end
