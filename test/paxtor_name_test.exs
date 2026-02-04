defmodule Paxtor.NameTest do
  use ExUnit.Case, async: false

  @moduletag :distributed

  setup_all do
    # Stop paxtor if it's already running
    Application.stop(:paxtor)
    Application.stop(:paxos_kv)

    # Ensure test node is distributed
    case Node.self() do
      :nonode@nohost ->
        {:ok, _} = Node.start(:"test@127.0.0.1", :longnames)
      _ ->
        :ok
    end


    # Build code path arguments for peer nodes - include both project and Elixir libs
    project_paths = Path.wildcard("_build/test/lib/*/ebin")
    elixir_paths = :code.get_path() |> Enum.map(&List.to_string/1)
    all_paths = (project_paths ++ elixir_paths)
    |> Enum.uniq()
    |> Enum.flat_map(fn path -> [~c"-pa", String.to_charlist(path)] end)

    # Start peer nodes - they will connect and see test node already running paxtor
    {:ok, peer1_pid, peer1} = :peer.start_link(%{
      name: :"peer1@127.0.0.1",
      longnames: true,
      args: all_paths,
      connection: :standard_io
    })

    {:ok, peer2_pid, peer2} = :peer.start_link(%{
      name: :"peer2@127.0.0.1",
      longnames: true,
      args: all_paths,
      connection: :standard_io
    })

    # Configure and start paxtor on peer nodes
    :ok = :erpc.call(peer1, Application, :put_env, [:paxos_kv, :cluster_size, 3])
    {:ok, _} = :erpc.call(peer1, :application, :ensure_all_started, [:paxtor])

    :ok = :erpc.call(peer2, Application, :put_env, [:paxos_kv, :cluster_size, 3])
    {:ok, _} = :erpc.call(peer2, :application, :ensure_all_started, [:paxtor])

    # Wait for cluster formation (all nodes should see each other)
    wait_for_cluster([peer1, peer2], 10_000)

    # NOW start Paxtor on ALL nodes (after they're all connected)
    # Configure cluster size BEFORE starting
    Application.put_env(:paxos_kv, :cluster_size, 3)
    {:ok, _} = Application.ensure_all_started(:paxtor)

    # Give the cluster a moment to fully initialize
    Process.sleep(2000)

    on_exit(fn ->
      # Gracefully stop peer nodes (may already be stopped)
      try do
        :peer.stop(peer1_pid)
      catch
        :exit, _ -> :ok
      end

      try do
        :peer.stop(peer2_pid)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(100)
    end)

    {:ok, cluster: %{peer1: peer1, peer2: peer2}}
  end

  defp wait_for_cluster(expected_peers, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_cluster(expected_peers, deadline)
  end

  defp do_wait_for_cluster(expected_peers, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      raise "Timeout waiting for cluster formation"
    end

    visible_nodes = Node.list()

    if Enum.all?(expected_peers, &(&1 in visible_nodes)) do
      :ok
    else
      Process.sleep(100)
      do_wait_for_cluster(expected_peers, deadline)
    end
  end

  # Group A: Basic Via Tuple Creation

  test "name/2 returns correct via tuple format for temporary" do
    via = Paxtor.name(:test_key, Counter)
    assert {:via, Paxtor.Spawn, {:test_key, Counter}} = via
  end

  test "different keys produce different via tuples" do
    via1 = Paxtor.name(:key1, Counter)
    via2 = Paxtor.name(:key2, Counter)

    assert via1 != via2
    assert {:via, Paxtor.Spawn, {:key1, Counter}} = via1
    assert {:via, Paxtor.Spawn, {:key2, Counter}} = via2
  end

  test "name/3 with :temporary returns correct via tuple" do
    via = Paxtor.name(:temp_key, Counter, restart: :temporary)
    assert {:via, Paxtor.Spawn, {:temp_key, Counter}} = via
  end

  # Group B: Process Starting and Message Passing

  test "calling Counter.inc/1 on via tuple starts the process" do
    via = Paxtor.name(:start_test, Counter)

    # Process should not exist yet
    assert Paxtor.lookup(via) == nil

    # First call should start process and return 1
    assert Counter.inc(via) == 1

    # Now process should exist
    pid = Paxtor.whereis(via)
    assert is_pid(pid)
    # Use node-aware alive check
    assert :erpc.call(node(pid), Process, :alive?, [pid])
  end

  test "Paxtor.lookup/1 returns nil before start, PID after" do
    via = Paxtor.name(:lookup_test, Counter)

    # Before starting
    assert Paxtor.lookup(via) == nil

    # Start the process
    Counter.inc(via)

    # After starting
    result = Paxtor.lookup(via)
    assert is_pid(result)
    # Use node-aware alive check
    assert :erpc.call(node(result), Process, :alive?, [result])
  end

  test "Paxtor.alive?/1 returns false/true correctly" do
    via = Paxtor.name(:alive_test, Counter)

    # Before starting
    refute Paxtor.alive?(via)

    # Start the process
    Counter.inc(via)

    # After starting
    assert Paxtor.alive?(via)
  end

  test "process maintains state between calls" do
    via = Paxtor.name(:state_test, Counter)

    # Multiple increments should maintain state
    assert Counter.inc(via) == 1
    assert Counter.inc(via) == 2
    assert Counter.inc(via) == 3
    assert Counter.inc(via) == 4
  end

  test "same PID throughout multiple calls" do
    via = Paxtor.name(:same_pid_test, Counter)

    # Start process
    Counter.inc(via)
    pid1 = Paxtor.whereis(via)

    # Multiple calls should use same PID
    Counter.inc(via)
    pid2 = Paxtor.whereis(via)

    Counter.inc(via)
    pid3 = Paxtor.whereis(via)

    assert pid1 == pid2
    assert pid2 == pid3
  end

  # Group C: Multiple Processes

  test "different keys result in different PIDs" do
    apple = Paxtor.name(:apple, Counter)
    banana = Paxtor.name(:banana, Counter)

    # Start processes
    Counter.inc(apple)
    Counter.inc(banana)

    # Verify different PIDs
    pid_apple = Paxtor.whereis(apple)
    pid_banana = Paxtor.whereis(banana)

    assert pid_apple != pid_banana
    # Use node-aware alive checks
    assert :erpc.call(node(pid_apple), Process, :alive?, [pid_apple])
    assert :erpc.call(node(pid_banana), Process, :alive?, [pid_banana])
  end

  test "3+ named processes are all alive simultaneously" do
    proc1 = Paxtor.name(:proc1, Counter)
    proc2 = Paxtor.name(:proc2, Counter)
    proc3 = Paxtor.name(:proc3, Counter)
    proc4 = Paxtor.name(:proc4, Counter)

    # Start all processes
    Counter.inc(proc1)
    Counter.inc(proc2)
    Counter.inc(proc3)
    Counter.inc(proc4)

    # Verify all are alive
    assert Paxtor.alive?(proc1)
    assert Paxtor.alive?(proc2)
    assert Paxtor.alive?(proc3)
    assert Paxtor.alive?(proc4)

    # Verify all have different PIDs
    pids = [
      Paxtor.whereis(proc1),
      Paxtor.whereis(proc2),
      Paxtor.whereis(proc3),
      Paxtor.whereis(proc4)
    ]

    assert length(Enum.uniq(pids)) == 4
  end

  test "separate processes maintain independent state" do
    counter_a = Paxtor.name(:counter_a, Counter)
    counter_b = Paxtor.name(:counter_b, Counter)

    # Increment counter_a multiple times
    assert Counter.inc(counter_a) == 1
    assert Counter.inc(counter_a) == 2
    assert Counter.inc(counter_a) == 3

    # Increment counter_b once
    assert Counter.inc(counter_b) == 1

    # counter_a should still be at 3, counter_b at 1
    assert Counter.inc(counter_a) == 4
    assert Counter.inc(counter_b) == 2
  end

  # Group D: Cross-Node Communication

  test "process started from test node is accessible from peer nodes", %{cluster: cluster} do
    via = Paxtor.name(:cross_node_test, Counter)

    # Start process from test node
    Counter.inc(via)
    test_pid = Paxtor.whereis(via)

    # Access from peer1
    peer1_result = :erpc.call(cluster.peer1, Counter, :inc, [via])
    assert peer1_result == 2

    # Access from peer2
    peer2_result = :erpc.call(cluster.peer2, Counter, :inc, [via])
    assert peer2_result == 3

    # Verify same PID
    peer1_pid = :erpc.call(cluster.peer1, Paxtor, :whereis, [via])
    peer2_pid = :erpc.call(cluster.peer2, Paxtor, :whereis, [via])

    assert test_pid == peer1_pid
    assert test_pid == peer2_pid
  end

  test "Counter.ping/1 verifies which node hosts the process", %{cluster: _cluster} do
    via = Paxtor.name(:ping_test, Counter)

    # Start process
    Counter.inc(via)
    pid = Paxtor.whereis(via)

    # Ping should return node and PID
    {:pong, node, returned_pid} = Counter.ping(via)

    assert is_atom(node)
    assert node == node(pid)
    assert returned_pid == pid
  end

  test "all nodes see same PID for given name", %{cluster: cluster} do
    via = Paxtor.name(:same_pid_cross_node, Counter)

    # Start process from test node
    Counter.inc(via)
    test_pid = Paxtor.whereis(via)

    # Check from peer1
    peer1_pid = :erpc.call(cluster.peer1, Paxtor, :whereis, [via])

    # Check from peer2
    peer2_pid = :erpc.call(cluster.peer2, Paxtor, :whereis, [via])

    # All should see same PID
    assert test_pid == peer1_pid
    assert test_pid == peer2_pid
  end

  # Group E: Temporary Restart Behavior

  test "process is NOT restarted after kill (temporary restart)" do
    via = Paxtor.name(:no_restart_test, Counter)

    # Start process
    Counter.inc(via)
    pid = Paxtor.whereis(via)

    # Kill the process (use node-aware exit)
    :erpc.call(node(pid), Process, :exit, [pid, :kill])

    # Wait a moment
    Process.sleep(100)

    # Process should NOT be restarted
    assert Paxtor.lookup(via) == nil
    refute Paxtor.alive?(via)
  end

  test "next call after crash starts NEW process with different PID" do
    via = Paxtor.name(:new_pid_after_crash, Counter)

    # Start process
    Counter.inc(via)
    old_pid = Paxtor.whereis(via)

    # Kill the process (use node-aware exit)
    :erpc.call(node(old_pid), Process, :exit, [old_pid, :kill])
    Process.sleep(100)

    # Next call should start a new process
    assert Counter.inc(via) == 1
    new_pid = Paxtor.whereis(via)

    assert new_pid != old_pid
    # Use node-aware alive check
    assert :erpc.call(node(new_pid), Process, :alive?, [new_pid])
  end

  test "state resets after crash (counter goes back to 1)" do
    via = Paxtor.name(:state_reset_test, Counter)

    # Increment several times
    Counter.inc(via)
    Counter.inc(via)
    Counter.inc(via)
    assert Counter.inc(via) == 4

    # Kill the process (use node-aware exit)
    pid = Paxtor.whereis(via)
    :erpc.call(node(pid), Process, :exit, [pid, :kill])
    Process.sleep(100)

    # Next call should start fresh at 1
    assert Counter.inc(via) == 1
    assert Counter.inc(via) == 2
  end
end
