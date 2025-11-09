  Resolves a name or name tuple to an actual pid (or port).

  It accepts locally registered process (or port) names, `:via` tuples, and
  also `{name, node}` tuples. It is a deliberate decision **not** to support
  `{:global, name}` tuples because:
  
  1. they interfere with `{name, node}` tuples
  2. there's no reason to use `:global` if you have Paxtor
  3. if you absolutely need `:global`, you can fall back to `{:via, :global,
     name}` and get the pid you need
