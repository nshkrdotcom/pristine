<p align="center">
  <img src="assets/pristine.svg" width="180" height="180" alt="Pristine logo" />
</p>

# Pristine

Pristine is a manifest-driven, hexagonal core for generating Elixir SDKs and service
clients. It separates domain logic from transport, retries, telemetry, and serialization
via ports and adapters, then renders SDK surfaces from declarative manifests.

## Highlights

- Ports and adapters architecture for transport, telemetry, retries, and serialization
- Manifest-first API definitions for endpoints, types, and policies
- Codegen pipeline for static modules or dynamic runtime rendering
- Sinter schemas for validation and JSON Schema generation
- Adapter-ready for Finch, foundation, multipart_ex, telemetry_reporter, tiktoken_ex

## Architecture

Pristine keeps core logic free of service specifics:

- Core: request pipeline, schema validation, response handling, error mapping
- Ports: transport, serializer, retry, telemetry, auth, circuit breaker, rate limit
- Adapters: Finch, foundation, telemetry_reporter, multipart_ex, tiktoken_ex
- Manifests: declarative API/type/policy definitions
- Codegen: render types and clients from manifests

## Manifest Example

```elixir
manifest = %{
  name: "tinkex",
  version: "0.3.4",
  endpoints: [
    %{
      id: "sample",
      method: "POST",
      path: "/sampling",
      request: "SampleRequest",
      response: "SampleResponse",
      retry: "default"
    }
  ],
  types: %{
    "SampleRequest" => %{
      fields: %{
        prompt: %{type: "string", required: true},
        sampling_params: %{type: "string", required: true}
      }
    }
  },
  policies: %{
    retry: %{"default" => %{max_attempts: 3}}
  }
}
```

## Generate Code

```bash
mix pristine.generate --manifest path/to/manifest.json --output lib/generated --namespace MySDK
```

## Example App

Run a local echo server and call it through Pristine:

```bash
mix run examples/demo.exs
```

## Development

```bash
mix deps.get
mix test
```

## Status

Early scaffolding. The core focuses on manifest normalization, port contracts,
and a minimal request pipeline with codegen hooks.
