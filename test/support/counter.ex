defmodule Counter do
  @moduledoc false

  #######################################
  ###  API

  def inc(counter) do
    GenServer.call(counter, :inc)
  end

  def ping(counter) do
    GenServer.call(counter, :ping)
  end

  #######################################
  ###  GenServer implementation

  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def init(_), do: {:ok, 1}

  def handle_call(:inc, _from, counter), do: {:reply, counter, counter + 1}
  def handle_call(:ping, _from, counter), do: {:reply, {:pong, Node.self(), self()}, counter}
end
