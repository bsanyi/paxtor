defmodule Paxtor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Paxtor.RegistrySupervisor,
      {PaxosKV.Bucket, bucket: Paxtor.Spawn},
      {PaxosKV.Bucket, bucket: Paxtor.Lock},
      {PaxosKV.PauseUntil, fn -> PaxosKV.Helpers.wait_for_bucket(Paxtor.Spawn) end},
      {PaxosKV.PauseUntil, fn -> PaxosKV.Helpers.wait_for_bucket(Paxtor.Lock) end}
    ]

    opts = [strategy: :one_for_one, name: Paxtor.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
