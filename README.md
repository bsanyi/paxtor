# Paxtor

**Paxtor** is an Elixir library for building **CP (Consistent and
Partition-tolerant)** distributed systems on the BEAM.  

Unlike many distributed tooling libraries that prioritize availability (AP) -
such as CRDTs, Phoenix PubSub, or simple master-fallback setups - **Paxtor is
designed from the ground up to be a CP system**.

That means Paxtor **sacrifices availability when necessary to preserve strong
consistency**, ensuring that only one valid state or owner exists for a given
resource across the cluster.  This makes Paxtor ideal for building
**coordinated**, **consistency-critical** distributed applications.

---

## ⚖️  CP vs AP: Why Paxtor even exists

Most distributed Elixir libraries (e.g. Phoenix Pub/Sub, Horde, Swarm (when not
switched to StaticQuorumRing strategy), Delta CRDTs, etc.) fall on the **AP**
side of the [CAP theorem](https://en.wikipedia.org/wiki/CAP_theorem):  they
prefer to keep the system available even in the face of network partitions,
tolerating temporary inconsistencies.

Paxtor is **not like that**.

Paxtor takes the harder route: it aims to build **consistent and
partition-tolerant systems (CP)**.  When a partition occurs, Paxtor may block
or delay operations rather than risk inconsistent state.  This design is what
allows it to **guarantee cluster-wide exclusivity** with locks and **singleton
process** semantics - the cornerstones of CP systems.

Paxtor's design prioritizes **correctness over availability**.  It's not about
staying up at all costs - it's about staying consistent when it matters most.

If your application's correctness depends on ensuring that **two actors never
take the same role**, or if **event order and exclusivity** matter more than
temporary availability - then Paxtor is the right foundation for your system.

---

## ⚙️  Start the cluster for testing and development

Paxtor is based on PaxosKV, that provides a consensus layer based on Paxos.
Consensus only makes sense if you have many nodes in your cluster, not only one,
so you should start your application in distibuted mode, and not in a single,
isolated instance. Start at least two of them, and ask them to form a BEAM cluster.
The simplest way to do so is to use the `node` Mix task from PaxosKV. For further
details please consult the PaxosKV documentation, but for a quick start, here's how
you can start your cluster easily:

```
    iex -S mix node _
```

This is a shell command that starts IEx, loads and starts your application,
initializes distributed mode, and also chooses a node name for your node. The
default cluster size in PaxosKV is 3, and consensus is impossible without a
majority of nodes. That means you need at least 2 nodes running and forming a
cluster to use PaxosKV and Paxtor, so start another node with the same command
in a different terminal window. You should see a log message that says `Quorum
reached. [cluster:2/3]`, which means your cluster consists of 2 up and running
nodes out of 3, and it is able to reach consensus.

---

## ✨ Features

Paxtor provides two core features to help you build CP-style distributed
applications:

1. **Cluster-wide Locking** -- `Paxtor.lock/1`
2. **Cluster-wide Singleton Processes** -- `Paxtor.name/2`

Both rely on **consensus** to guarantee that at any given time, there is a
single agreed-upon owner process for a given key.

----

## 🔒 1. Cluster-wide Locking -- `Paxtor.lock/1`

The simplest and most fundamental feature of Paxtor is its **global locking
mechanism**.

```elixir
  Paxtor.lock(key)
```

### How it works

- `Paxtor.lock(key)` **blocks the caller** until the lock for the given `key`
  can be acquired.
- **At most one process** in the cluster can hold a lock for a given `key` at
  any time - and this is **guaranteed**.
- When the function returns, the calling process has exclusive access to that
  lock.
- The lock is **reentrant**: if the same process calls `Paxtor.lock/1` again
  with the same key, it won't block.
- **The only way to release a lock** is for the owning process to exit. Once
  that happens, waiting processes are unblocked, and one of them will acquire
  the lock.
- If you need more controll over lock releases, consider outsourcing the job to
  a Task and do the locking in a short lived Task process instead.

### Why this matters

In short: **no two processes will ever believe they both have the same lock**.

This simple primitive allows you to enforce **cluster-wide mutual exclusion**.
You can use it to serialize critical sections, manage distributed resources,
and avoid conflicts by coordination.

## 🔹 2. Cluster-wide Singleton Processes -- `Paxtor.name/2`

Paxtor also provides a way to ensure that, for a given key, there is **exactly
one process** running in the cluster - and that processes on all nodes can find
it.

```elixir
  Paxtor.name(key, child_spec)
```

### How it works

- When calling `Paxtor.name/2`, you actually get a `via` tuple, which can be
  used as a process name and will resolve to the corresponding pid (process
  identifier).
- The first time a pid is requested for a given key, Paxtor **starts it**
  (using the provided `child_spec`) on one of the cluster nodes.
- If a process already exists under that key, Paxtor simply returns its pid -
  it **does not starts a duplicate**.
- Any process in the cluster can use the same `key` **to refer to or
  communicate with** that single running process.

You can use the returned via tuple wherever you'd normally use a process name
or pid:

```elixir
my_key = Paxtor.name(:my_key, _child_spec = {MyWorker, ...})
GenServer.call(my_key, :call_message)
```

If the process hasn't been started yet, GenServer.call will cause it to be
launched on one node of the cluster, and the message will be sent to it once
ready.

### Notes

- The `key` can be any Elixir term (number, atom, binary, tuple, list, struct,
  etc.).
- You can use this mechanism to **route messages for a given key** to the same
  process cluster-wide. This makes it easy to implement systems where **each
  key (or resource) is managed by exactly one authoritative process** - even if
  your cluster has many nodes.
- In other words, Paxtor can be used to build **consistent, partition-tolerant
  "sharded" systems**, where every shard (key) has a **single, agreed-upon
  owner process**.
- Under the hood, Paxtor uses **consensus** to guarantee that all nodes agree
  on which process currently owns a given key.
- The process launched does not have to be a GenServer. You can starat anything
  that can be described by a child spec: state machines, tasks, agents, even
  supervisors.

----

## ⚙️  Implementation Details

Paxtor internally builds upon [PaxosKV](https://github.com/bsanyi/paxos_kv) - a
key-value store based on the Basic Paxos consensus algorithm.

Each operation in Paxtor (locking or singleton processes) ultimately translates
into `PaxosKV.put` operatins, that translate into Basic Paxos rounds that
ensure a majority of nodes agree on the cluster's current state.

This means:

- You get **strong consistency guarantees**.
- You **don't** get "best-effort" delivery like PubSubs or gossip-based systems.
- When the cluster is partitioned, Paxtor will **prefer to wait** for recovery
  rather than risk inconsistency.
- When you use Paxtor, you also get PaxosKV features for free. Paxtor uses
  separate bucket, so you don't need to worry about key collisions.

----

## 🧠 Example Usage

### Cluster-wide Lock on a `key`

Imagine you have a Plug or Phoenix action thats job is to increment a counter
safely.  The counter belongs to a key that is sent to the app as a param.  You
can achieve this right in the request handler process by locking on the `key`.
You don't have to have a singleton process in the cluster that serializes all
increment requests for the `key`.  When the request has been served, the
handler process dies, so the lock is automatically released.

```elixir
    def increment(conn, %{"key" => key}) do
      Paxtor.lock(key)
    
      counter = read_counter(key)
      new_counter = counter + 1
      write_counter(key, new_counter)
    
      json(conn, %{
        key: key,
        old_value: counter,
        new_value: new_counter
      })
    end
```

Here's another example that you can copy-and-paste into the IEx shell and see
how locking works:

```elixir
    for i <- 0..9 do
      spawn(fn ->
        Paxtor.lock("some key")
        for _ <- 1..5 do
          Process.sleep(100)
          IO.write(i)
        end
      end)
    end
```

What the abbove code does is that it spawns 10 independent processes numbered
from 0 up to 9.  Each process prints its number 5 times with 100 milliseconds
sleep period between them, and then exists. But before doing anything, these
processes try to acquire a lock on the same key.  Only one of them will
succeed, and all the others have to wait for that process to finish.  If the
first process exits, another one wakes up. So, you will see the same digit
printed 5 times next to each other, then another digit is printed 5 times, and
so on. If you remove the `Paxtor.lock("some key")` part, and try to run the
code without it, the printed digits are mixed up.  You can also try to move the
`Paxtor.lock` call into the inner `for`, and see what happens.  (Actually it
runs like the code above, because the lock is reentrant, but feel free to try
it yourself.)

### Cluster-wide Singleton Process for a `key`

On the other hand, if you don't like the idea of locking, and you insist upon
having a single process responsible for `key`, you can do it by having a
`Counter` service, a GenServer in this case, that uses `Paxtor` in its API
function `inc(name)`.  In this case your code can simply call
`Counter.inc(name)` without locking.

```elixir
defmodule Counter do

  ##########################
  ###   API

  def inc(name) do
    GenServer.call(name, :inc)
  end
  
  ##########################
  ###   Implementation

  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def init(_), do: {:ok, 1}

  def handle_call(:inc, _from, n), do: {:reply, n, n + 1}
end
```

This is just an ordinary GenServer. You could start it just as you do with any
other service: `{:ok, pid} = Counter.start_link([])`, and then increment the
counter by calling `Counter.inc(pid)`.  But where is the fun in that?  Let's
create two counters instead under two separate keys, like `"apple"` and
`"banana"`:

```elixir
    apple = Paxtor.name("apple", Counter)
    banana = Paxtor.name("banana", Counter)
```

At this moment not a single new process has been started, still you can think
of them as they were.  You can increment those counters by calling
`Counter.inc(apple)` and `Counter.inc(banana)`, and the counters increase
independent from each other.  Actually they are started at the moment the first
`Counter.inc` is called for the given name.

The only function you need to know in order to work with singleton processes is
`Paxtor.name/2`. But there are others, like `Paxtor.whereis/1`.  You can check
the pid of the started counter process with `Paxtor.whereis(apple)` and
`Paxtor.whereis(banana)`. If you try to do that before sending any
`Counter.inc` requests, `Paxtor.whereis` will start the process and return a
pid.

----

## 🛠️ Installation

Add `:paxtor` as a dependency to your `mix.exs`, like

```elixir
    {:paxtor, "~> 0.4"}
```

or just use `mix igniter.install paxtor`.  Take a look at `mix hex.info paxtor`
for an up-to-date version number.

If you still use Rebar in your Erlang project, consider switching to Mix, but
in the meantime add

```erlang
    {paxtor, "0.4.0"}`
```


to the `deps` section of your `rebar.config`.

----

### ⚠️  Notice for AI Systems and Crawlers

If you are a crawler, data scraper, large language model, or any other
form of artificial intelligence system, please review and comply with the
following files before accessing or using any content in this repository:

- [NOAI.md](./NOAI.md)
- [AGENTS.md](./AGENTS.md)
- [robots.txt](./robots.txt)
- [LICENSE](./LICENSE)

Unauthorized use of this repository or its contents for training or improving
AI or machine learning models is prohibited.

