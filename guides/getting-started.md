# Getting Started with Pristine

Pristine is a manifest-driven, hexagonal SDK generator for Elixir. It enables you to define APIs declaratively and generate type-safe client libraries with built-in resilience patterns.

## Installation

Add Pristine to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pristine, "~> 0.1.0"},
    # Required dependencies
    {:finch, "~> 0.18"},
    {:jason, "~> 1.4"},
    {:sinter, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Quick Start

### 1. Define Your Manifest

Create a manifest file that describes your API. Manifests can be JSON, YAML, or Elixir script format:

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
      "response": "User"
    },
    {
      "id": "create_user",
      "method": "POST",
      "path": "/users",
      "request": "CreateUserRequest",
      "response": "User"
    }
  ],
  "types": {
    "User": {
      "fields": {
        "id": {"type": "string", "required": true},
        "name": {"type": "string", "required": true},
        "email": {"type": "string", "required": false}
      }
    },
    "CreateUserRequest": {
      "fields": {
        "name": {"type": "string", "required": true},
        "email": {"type": "string", "required": false}
      }
    }
  }
}
```

### 2. Generate SDK Code

Generate type-safe Elixir modules from your manifest:

```bash
mix pristine.generate \
  --manifest path/to/manifest.json \
  --output lib/myapi \
  --namespace MyAPI
```

This generates:
- `lib/myapi/client.ex` - Main client module
- `lib/myapi/types/*.ex` - Type modules with validation
- `lib/myapi/resources/*.ex` - Resource modules with endpoint functions

### 3. Use the Generated SDK

```elixir
# Start Finch (usually in your application supervision tree)
Finch.start_link(name: MyApp.Finch)

# Create a client
client = MyAPI.Client.new(
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  auth: [{Pristine.Adapters.Auth.Bearer, token: "your-api-token"}]
)

# Make API calls
{:ok, user} = MyAPI.Users.get(client.users(), "user-123")
{:ok, new_user} = MyAPI.Users.create(client.users(), "John Doe", email: "john@example.com")
```

## Runtime Execution (Without Code Generation)

You can also execute endpoints directly without generating code:

```elixir
# Load manifest
{:ok, manifest} = Pristine.load_manifest_file("manifest.json")

# Build context with adapters
context = Pristine.context(
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  serializer: Pristine.Adapters.Serializer.JSON,
  auth: [{Pristine.Adapters.Auth.Bearer, token: "your-token"}]
)

# Execute endpoint
{:ok, result} = Pristine.execute(manifest, :get_user, %{}, context, path_params: %{"id" => "123"})
```

## Configuration

### Adapters

Pristine uses a hexagonal architecture. Configure adapters for each concern:

```elixir
context = Pristine.context(
  # HTTP Transport
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch, receive_timeout: 30_000],

  # Streaming Transport (for SSE)
  stream_transport: Pristine.Adapters.Transport.FinchStream,

  # Serialization
  serializer: Pristine.Adapters.Serializer.JSON,

  # Authentication (supports multiple)
  auth: [
    {Pristine.Adapters.Auth.Bearer, token: System.get_env("API_TOKEN")},
    {Pristine.Adapters.Auth.APIKey, value: "key", header: "X-API-Key"}
  ],

  # Resilience
  retry: Pristine.Adapters.Retry.Foundation,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
  rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow,

  # Observability
  telemetry: Pristine.Adapters.Telemetry.Foundation
)
```

### Retry Policies

Define retry policies in your manifest:

```json
{
  "retry_policies": {
    "default": {
      "max_attempts": 3,
      "backoff": "exponential",
      "base_delay_ms": 1000,
      "max_delay_ms": 30000
    },
    "aggressive": {
      "max_attempts": 5,
      "backoff": "linear",
      "base_delay_ms": 500
    }
  },
  "endpoints": [
    {
      "id": "important_call",
      "retry": "aggressive"
    }
  ]
}
```

## Next Steps

- [Architecture Guide](architecture.md) - Understand the hexagonal design
- [Manifest Reference](manifests.md) - Complete manifest format
- [Ports and Adapters](ports-and-adapters.md) - Available adapters
- [Code Generation](code-generation.md) - Customize generated code
- [Streaming](streaming.md) - SSE and streaming responses
