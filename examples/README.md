# Pristine Examples

## Demo

Run a local echo server and execute a manifest-defined call through Pristine:

```bash
mix deps.get
mix run examples/demo.exs
```

This spins up a local Plug server on port 4041 and issues a POST request using
Finch + the manifest pipeline.
