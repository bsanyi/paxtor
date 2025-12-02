defmodule Paxtor.Lock do
  @moduledoc """
  The module `Paxtor.Lock` is the home of the cluster-wide locking mechanism.

  See `Paxtor.lock` for futher details.
  """

  require Logger

  def lock(key, opts) do
    block? = Keyword.get(opts, :block, true)
    no_quorum = Keyword.get(opts, :no_quorum, :retry)

    me = self()

    case PaxosKV.put(key, me, pid: me, bucket: __MODULE__, no_quorum: no_quorum) do
      {:ok, ^me} ->
        Logger.debug(
          "Process #{inspect(me)} on node #{Node.self()} acquired lock for #{inspect(key)}."
        )

        :acquired

      {:ok, pid} when is_pid(pid) and block? ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> lock(key, opts)
        end

      {:ok, pid} when is_pid(pid) ->
        {:held_by, pid}

      {:error, :no_quorum} ->
        Logger.warning("No quorum reached for lock acquisition for #{inspect(key)}.")
        :no_quorum
    end
  end
end
