-module(paxtor).

-moduledoc """
**Paxtor** is an Elixir library for building **CP (Consistent and
Partition-tolerant)** distributed systems on the BEAM.

This module is the Erlang API of Paxtor. It allows you to use Paxtor
from Erlang with a more natural syntax. For example:

```erlang
paxtor:lock(Key).
```
""".

-export([lock/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-doc """
Acquires a cluster-wide lock on a resource represented by `Key`.

For further information please consult the Elixir documentation of
`Paxtor.lock/1` or the content of the file `doc/lock.md`.
""".

lock(Key) ->
  'Elixir.Paxtor.Lock':lock(Key).

