It spawns a temporary singleton process in the cluster.

By _temporary_ I mean it is not restarted when it exits, no matter what the
exit reason is.  If it stops, another process can be started under the same
`key` with another call to `spawn/2`.

The return value of the call is the pid of the process.  If the process already
run, no new process is created, but the old pid is returned.  Also mind that
the process can run on any node of the cluster, and it isn't necessarily a
local process.

If you don't want to actually start the process, but you need a recipe, a
deferred way of spawning it (like a Stream, instead of a List), you can use
`Paxtor.Spawn.via(key, child_spec)`.  This returns a `:via` tuple that. Ehen
resolved to a pid, it does what `spawn(key, child_spec)` does immediately.
Please also look at `Paxtor.whereis/1` if you decide to work with `:via`
tuples.
