# Pristine Workspace Examples

This workspace keeps examples intentionally small. Runtime-facing examples live
with the runtime package so they can evolve alongside the code they exercise.

## Runtime Demo

The runtime example now lives with the runtime package:

```bash
cd apps/pristine_runtime
mix run examples/demo.exs
```

It spins up a local Plug server on port `4041` and issues a request through the
runtime package's current `Pristine.execute/3` boundary.
