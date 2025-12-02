defmodule Paxtor.RegistryBehaviour do
  @callback whereis_name(name :: term()) :: pid()

  @callback register_name(name :: term(), pid :: pid()) :: :yes | :no

  @callback unregister_name(name :: term()) :: :ok

  @callback send(name :: term(), message :: term()) :: term()

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Paxtor.RegistryBehaviour

      @impl true
      def register_name(_name, _pid), do: :no

      @impl true
      def unregister_name(_name), do: :ok

      @impl true
      def send(name, message) do
        name
        |> whereis_name()
        |> Kernel.send(message)
      end

      defoverridable register_name: 2, unregister_name: 1, send: 2
    end
  end

  def whereis(name) when is_atom(name), do: Process.whereis(name)

  def whereis({name, node}) when is_atom(name) and is_atom(node),
    do: :erpc.call(node, Process, :whereis, [name])

  def whereis({:via, module, name}), do: module.whereis_name(name)
  def whereis({:global, name}), do: whereis({:via, :global, name})
end
