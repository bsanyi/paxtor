defmodule Paxtor.Lock do
  @moduledoc """
  The module `Paxtor.Lock` is the home of the cluster-wide locking mechanism.

  See `Paxtor.lock` for futher details.

  This module can also be used in via tuples as a registry to reference the
  `pid` of a process that owns a lock.

      iex> Paxtor.lock(:some_key)
      iex> Paxtor.whereis({:via, #{inspect(__MODULE__)}, :some_key}) == self()
      true
      iex> #{inspect(__MODULE__)}.whereis_name(:some_key) == self()
      true

  """

  def lock(key, opts) do
    block? = Keyword.get(opts, :block, true)
    no_quorum = Keyword.get(opts, :no_quorum, :retry)

    me = self()

    case PaxosKV.put(key, me, pid: me, bucket: __MODULE__, no_quorum: no_quorum) do
      {:ok, ^me} ->
        :acquired

      {:ok, pid} when is_pid(pid) and block? ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> lock(key, opts)
        end

      {:ok, pid} when is_pid(pid) ->
        {:held_by, pid}

      {:error, :no_quorum} when block? ->
        :erlang.yield()
        lock(key, opts)

      {:error, :no_quorum} ->
        :no_quorum
    end
  end

  @doc """
  This function returns a `:via` tuple that uses the current module as the
  regitry module. The purpose of this is to allow processes to get the pid of a
  process holding a lock.

      iex> key |> #{inspect(__MODULE__)}.via() |> Paxtor.whereis()

  """
  def via(key) do
    {:via, __MODULE__, key}
  end

  @doc """
  This is the API function that makes it possible to use #{__MODULE__} in
  `:via` tuples.  You can also call this function directly to get the pid
  of the process currenty associated with a lock.
  """
  def whereis_name(key) do
    case PaxosKV.get(key, bucket: __MODULE__, no_quorum: :return) do
      {:ok, pid} when is_pid(pid) -> pid
      _ -> :unknown
    end
  end

  @doc false
  def register_name(key, pid) when is_pid(pid) do
    case PaxosKV.put(key, pid, pid: pid, bucket: __MODULE__, no_quorum: :return) do
      {:ok, ^pid} -> :yes
      _ -> :no
    end
  end

  @doc false
  def unregister_name(_key), do: :ok

  @doc false
  def send(key, message) do
    case whereis_name(key) do
      pid when is_pid(pid) ->
        Kernel.send(pid, message)
        pid

      _ ->
        exit({:badarg, {key, message}})
    end
  end
end
