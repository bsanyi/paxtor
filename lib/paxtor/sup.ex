defmodule Paxtor.Sup do
  use Supervisor

  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: Keyword.get(opts, :id, Keyword.get(opts, :name)))
  end

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, [], opts)

  @impl true
  def init(_), do: Supervisor.init([], strategy: :one_for_one, max_restarts: 1000)

  def exec_in_supervisor(supervisor, fun) when is_function(fun) do
    supervisor = Paxtor.whereis(supervisor)

    caller = self()
    id = make_ref()

    f = fn ->
      value = fun.()
      Kernel.send(caller, {id, value})
      :ignore
    end

    Supervisor.start_child(supervisor, %{id: id, start: {Kernel, :apply, [f, []]}})
    # Supervisor.delete_child(supervisor, id)

    receive do
      {^id, value} -> value
    end
  end

  def pid(supervisor, key) do
    supervisor
    |> Paxtor.whereis()
    |> Supervisor.which_children()
    |> Enum.find_value(fn {id, pid, _, _} -> id == key && pid end)
  end
end
