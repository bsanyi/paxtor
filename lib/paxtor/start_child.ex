defmodule Paxtor.StartChild do
  @supervisor Module.concat(__MODULE__, Supervisor)

  @doc """
  Ensures the process represented by `key` and `child_spec` is started, and it
  returns the pid of the process.  In case of an unexpected problem it can
  return `:undefined` or `nil`.
  """
  def ensure_started(key, child_spec) do
    node = primary_node(key)

    Supervisor.start_child({@supervisor, node}, custom_child_spec(key, child_spec))
    |> tap(&start_others(&1, key, child_spec, [node]))
    |> Paxtor.Helpers.pid_from()
  end

  @doc """
  Returns the pid of the process behind `key`.  If the process in not yet
  started, it starts the process using `child_spec` and returns the newly
  created pid.
  """
  def whereis(key, child_spec) do
    node = primary_node(key)
    Paxtor.whereis({via(key, child_spec), node})
  end

  def lookup(key) do
    case PaxosKV.get(key, bucket: __MODULE__, no_quorum: :retry) do
      {:ok, node} ->
        if Node.ping(node) == :pong do
          Paxtor.Sup.pid({@supervisor, node}, key)
        else
          nil
        end

      {:error, :not_found} ->
        nil
    end
  end

  @doc """
  Returns a `:via` tuple that represents the process behind the `key`.

  Ths via tuple can be used in place of a process name, and it resolves to the
  pid behind `key`. To resolve it, you can use `Paxtor.whereis/`, or most of
  the standart OTP functions that take not only pids, but also process names,
  like `GenServer.call`.

  There is no process started by just creating a via tuple, but resolving the
  via tuple (like `Paxtor.whereis(via_tuple)`) starts the process in case it
  was not started yet.
  """
  def via(key, child_spec) do
    {:via, __MODULE__, {key, child_spec}}
  end

  @doc """
  Checks if the given `key` has a running, alive process in the cluster.
  """
  def alive?(key) do
    key
    |> lookup()
    |> is_pid()
  end

  use Paxtor.RegistryBehaviour

  @doc false
  @impl Paxtor.RegistryBehaviour
  def whereis_name({key, child_spec}), do: ensure_started(key, child_spec)

  defp primary_node(key) do
    with [_ | _] = nodes <- PaxosKV.Cluster.nodes(),
         node <- Enum.random(nodes),
         {:ok, node} <- PaxosKV.put(key, node, bucket: __MODULE__, node: node, no_quorum: :retry)
    do
      node
    else
      [] ->
        PaxosKV.Helpers.random_backoff()
        primary_node(key)

      {:error, :invalid_value} ->
        primary_node(key)
    end
  end

  defp custom_child_spec(key, child_spec) do
    child_spec = Supervisor.child_spec(child_spec, id: key)

    Supervisor.child_spec(child_spec,
      start: {__MODULE__, :custom_start_link, [key, child_spec]},
      restart: :permanent
    )
  end

  @doc false
  def custom_start_link(key, child_spec) do
    my_node = Node.self()

    case primary_node(key) do
      ^my_node ->
        child_spec.start
        |> then(fn {m, f, a} -> apply(m, f, a) end)
        |> tap(&start_others(&1, key, child_spec, [my_node]))

      node when is_atom(node) ->
        Paxtor.StartChild.Monitor.start_link(key, custom_child_spec(key, child_spec))
    end
  end

  defp start_others(result, key, child_spec, except) do
    case Paxtor.Helpers.pid_from(result) do
      pid when is_pid(pid) ->
        spawn(fn ->
          Paxtor.Helpers.start_children(custom_child_spec(key, child_spec), @supervisor,
            except: except
          )
        end)

      _ ->
        nil
    end
  end
end
