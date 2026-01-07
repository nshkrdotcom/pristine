<p align="center">
  <img src="assets/pristine.svg" width="200" height="200" alt="Pristine logo" />
</p>

<h1 align="center">Pristine</h1>

<p align="center">
  <strong>Manifest-driven, hexagonal SDK generator for Elixir</strong>
</p>

<p align="center">
  <a href="https://hex.pm/packages/pristine"><img src="https://img.shields.io/hexpm/v/pristine.svg" alt="Hex Version" /></a>
  <a href="https://hexdocs.pm/pristine"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs" /></a>
  <a href="https://github.com/nshkrdotcom/pristine/actions"><img src="https://img.shields.io/github/actions/workflow/status/nshkrdotcom/pristine/ci.yml?branch=master" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License" /></a>
</p>

---

Pristine separates domain logic from infrastructure through a clean ports and adapters architecture. Define your API in a declarative manifest, then generate type-safe Elixir SDKs with built-in resilience patterns, streaming support, and comprehensive observability.

## Features

- **Hexagonal Architecture** — Clean separation via ports (interfaces) and adapters (implementations)
- **Manifest-Driven** — Declarative API definitions in JSON, YAML, or Elixir
- **Code Generation** — Generate type modules, resource modules, and clients from manifests
- **Type Safety** — Sinter schema validation for requests and responses
- **Resilience Built-In** — Retry policies, circuit breakers, and rate limiting
- **Streaming Support** — First-class SSE (Server-Sent Events) handling
- **Observable** — Telemetry events throughout the request lifecycle
- **Extensible** — Swap adapters for transport, auth, serialization, and more

## Installation

Add Pristine to your dependencies:

```elixir
def deps do
  [
    {:pristine, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define Your API Manifest

```json
{
  "name": "myapi",
  "version": "1.0.0",
  "base_url": "https://api.example.com",
  "endpoints": [
    {
      "id": "get_user",
      "method": "GET",
      "path": "/users/{id}",
      "resource": "users",
      "response": "User"
    },
    {
      "id": "create_user",
      "method": "POST",
      "path": "/users",
      "resource": "users",
      "request": "CreateUserRequest",
      "response": "User"
    }
  ],
  "types": {
    "User": {
      "fields": {
        "id": {"type": "string", "required": true},
        "name": {"type": "string", "required": true},
        "email": {"type": "string"}
      }
    },
    "CreateUserRequest": {
      "fields": {
        "name": {"type": "string", "required": true},
        "email": {"type": "string"}
      }
    }
  }
}
```

### 2. Generate SDK Code

```bash
mix pristine.generate \
  --manifest manifest.json \
  --output lib/myapi \
  --namespace MyAPI
```

### 3. Use the Generated SDK

```elixir
# Create a client
client = MyAPI.Client.new(
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  auth: [{Pristine.Adapters.Auth.Bearer, token: "your-token"}]
)

# Make API calls
{:ok, user} = MyAPI.Users.get(client.users(), "user-123")
{:ok, new_user} = MyAPI.Users.create(client.users(), "John Doe", email: "john@example.com")
```

## Architecture

Pristine implements a hexagonal (ports and adapters) architecture:

```
┌─────────────────────────────────────────────────────────┐
│                    Your Application                     │
├─────────────────────────────────────────────────────────┤
│                  Generated SDK Layer                    │
│              (Client, Resources, Types)                 │
├─────────────────────────────────────────────────────────┤
│                    Pristine Core                        │
│      Pipeline │ Manifest │ Codegen │ Streaming          │
├─────────────────────────────────────────────────────────┤
│                        Ports                            │
│    Transport │ Serializer │ Auth │ Retry │ Telemetry    │
├─────────────────────────────────────────────────────────┤
│                       Adapters                          │
│     Finch │ JSON │ Bearer │ Foundation │ Gzip │ SSE     │
└─────────────────────────────────────────────────────────┘
```

**Ports** define interface contracts. **Adapters** provide implementations. Swap adapters to change behavior without touching domain logic.

## Available Adapters

| Category | Adapters |
|----------|----------|
| **Transport** | Finch, FinchStream |
| **Serializer** | JSON |
| **Auth** | Bearer, APIKey |
| **Retry** | Foundation, Noop |
| **Circuit Breaker** | Foundation, Noop |
| **Rate Limit** | BackoffWindow, Noop |
| **Telemetry** | Foundation, Raw, Reporter, Noop |
| **Compression** | Gzip |
| **Streaming** | SSE |

## Runtime Execution

Execute endpoints without code generation:

```elixir
# Load manifest
{:ok, manifest} = Pristine.load_manifest_file("manifest.json")

# Build context with adapters
context = Pristine.context(
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  serializer: Pristine.Adapters.Serializer.JSON,
  auth: [{Pristine.Adapters.Auth.Bearer, token: "your-token"}],
  retry: Pristine.Adapters.Retry.Foundation,
  telemetry: Pristine.Adapters.Telemetry.Foundation
)

# Execute endpoint
{:ok, result} = Pristine.execute(manifest, :get_user, %{}, context,
  path_params: %{"id" => "123"}
)
```

## Streaming Support

Handle SSE streams with first-class support:

```elixir
context = Pristine.context(
  stream_transport: Pristine.Adapters.Transport.FinchStream,
  # ... other config
)

{:ok, response} = Pristine.Core.Pipeline.execute_stream(
  manifest, :stream_endpoint, payload, context
)

# Consume events lazily
response.stream
|> Stream.each(fn event ->
  case Pristine.Streaming.Event.json(event) do
    {:ok, data} -> process(data)
    {:error, _} -> :skip
  end
end)
|> Stream.run()
```

## Resilience Patterns

Configure retry policies in your manifest:

```json
{
  "retry_policies": {
    "default": {
      "max_attempts": 3,
      "backoff": "exponential",
      "base_delay_ms": 1000
    }
  },
  "endpoints": [
    {
      "id": "important_call",
      "retry": "default"
    }
  ]
}
```

Built-in support for:
- **Exponential backoff** with jitter
- **Circuit breakers** per endpoint
- **Rate limiting** with server-driven backoff
- **Idempotency keys** for safe retries

## Documentation

- [Getting Started](guides/getting-started.md) — Installation and quick start
- [Architecture](guides/architecture.md) — Hexagonal design overview
- [Manifests](guides/manifests.md) — Complete manifest reference
- [Ports & Adapters](guides/ports-and-adapters.md) — Available adapters
- [Code Generation](guides/code-generation.md) — Customize generated code
- [Streaming](guides/streaming.md) — SSE and streaming responses
- [Pipeline](guides/pipeline.md) — Request execution internals

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Type checking
mix dialyzer

# Linting
mix credo --strict

# Format code
mix format

# Run all checks
mix test && mix dialyzer && mix credo --strict
```

## Dependencies

Pristine integrates with several companion libraries:

| Library | Purpose |
|---------|---------|
| [Foundation](https://github.com/nshkrdotcom/foundation) | Retry, backoff, circuit breaker |
| [Sinter](https://github.com/nshkrdotcom/sinter) | Schema validation |
| [Finch](https://hex.pm/packages/finch) | HTTP client |
| [Jason](https://hex.pm/packages/jason) | JSON encoding |

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to the [GitHub repository](https://github.com/nshkrdotcom/pristine).

## License

MIT License. See [LICENSE](LICENSE) for details.
