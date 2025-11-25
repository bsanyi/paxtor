defmodule Paxtor.Helpers do
  def start_children(child_spec, supervisor, opts \\ []) do
    for node <- PaxosKV.Cluster.nodes() -- Keyword.get(opts, :except, []) do
      {node, Supervisor.start_child({supervisor, node}, child_spec)}
    end
  end

  @doc """
  When a `start_link` or `Supervisor.start_child` is called, it can return
  different kind of answers. The happy path is usually `{:ok, pid}` or `{:ok,
  pid, info}`, so we can grab the pid from these cases. Also when a
  `start_child` is called and the supervisor already has a child with the given
  id, it returns `{:error, {:already_started, pid}}`, and we strill can get a
  `pid`. But in the error cases, like in case of an `:ignore` or `{:error,
  reason}` value, there's no `pid`. This function pattern matches and returns
  the pid from the positive cases.
  """
  def pid_from({:ok, pid}) when is_pid(pid), do: pid
  def pid_from({:ok, pid, _info}) when is_pid(pid), do: pid
  def pid_from({:error, {:already_started, pid}}) when is_pid(pid), do: pid
  def pid_from(_), do: nil
end
