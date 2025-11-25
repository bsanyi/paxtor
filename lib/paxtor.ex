defmodule Paxtor do
  @moduledoc """
  `Paxtor` is the API module of the Paxtor application.
  """

  @doc File.read!("docs/name.md")
  def name(key, child_spec) do
    Paxtor.Spawn.via(key, child_spec)
  end

  @doc File.read!("docs/spawn.md")
  def spawn(key, child_spec) do
    whereis(Paxtor.Spawn.via(key, child_spec))
  end

  # def start_child(key, child_spec) do
  #   :not_yet_implemented
  # end

  @doc File.read!("docs/whereis.md")
  def whereis(pid) when is_pid(pid), do: pid
  def whereis(name) when is_atom(name), do: Process.whereis(name)
  def whereis({:via, module, name}), do: module.whereis_name(name)
  def whereis({name, node}) when is_atom(node), do: :erpc.call(node, Paxtor, :whereis, [name])

  @doc File.read!("docs/lock.md")
  def lock(key, opts \\ []) do
    Paxtor.Lock.lock(key, opts)
  end
end
