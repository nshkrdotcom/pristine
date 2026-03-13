# Getting Started with Pristine

Pristine is a manifest-driven, hexagonal SDK generator for Elixir. It enables you to define APIs declaratively and generate type-safe client libraries with built-in resilience patterns.

## Installation

Add Pristine to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pristine, "~> 0.1.0"},
    {:oauth2, "~> 2.1"}, # Optional: only needed for Pristine.OAuth2 helpers
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

`oauth2` is optional. Normal request execution and generated SDK clients continue to use Pristine's transport boundary directly.

## Quick Start

### 1. Define Your Manifest

Create a manifest file that describes your API. File-based manifests can be JSON or YAML:

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
resource = MyAPI.Client.users(client)
{:ok, user} = MyAPI.Users.get(resource, "user-123")
{:ok, new_user} = MyAPI.Users.create(resource, "John Doe", email: "john@example.com")
```

## Runtime Execution (Without Code Generation)

You can also execute endpoints directly without generating code:

```elixir
# Load manifest
{:ok, manifest} = Pristine.load_manifest_file("manifest.json")

# Build a production context
context = Pristine.foundation_context(
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  serializer: Pristine.Adapters.Serializer.JSON,
  auth: [{Pristine.Adapters.Auth.Bearer, token: "your-token"}],
  telemetry: [namespace: [:my_api]]
)

# Execute endpoint
{:ok, result} = Pristine.execute(manifest, :get_user, %{}, context, path_params: %{"id" => "123"})
```

If you are using OpenAPI-generated schema refs in the manifest or generated client, pass `typed_responses: true` per call when you want successful responses materialized through the generated `decode/1,2` helpers instead of returning validated maps.

## Configuration

### Adapters

Pristine uses a hexagonal architecture. For production callers, start with the
shared Foundation-backed profile:

```elixir
context = Pristine.foundation_context(
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

  # Cohesive production seams
  retry: [max_attempts: 3],
  rate_limit: [key: {:my_app, :my_api}, registry: MyApp.RateLimits],
  circuit_breaker: [registry: MyApp.Breakers],

  # Structured telemetry
  telemetry: [namespace: [:my_api], metadata: %{service: :my_api}]
)
```

`Pristine.context/1` remains available when you want to wire each adapter
manually or disable the profile entirely.

If your API uses OpenAPI-style `security` metadata, `auth` can also be a map keyed by security-scheme name:

```elixir
context = Pristine.context(
  auth: %{
    "bearerAuth" => [
      Pristine.Adapters.Auth.OAuth2.new(
        token_source: {MyApp.TokenSource, account_id: "acct_123"}
      )
    ],
    "basicAuth" => []
  }
)
```

For interactive authorization-code flows, reuse `Pristine.OAuth2.Interactive`
so Pristine owns the browser handling, loopback callback capture, and manual
paste-back path:

```elixir
provider =
  Pristine.OAuth2.Provider.new(
    name: "example",
    site: "https://api.example.com",
    authorize_url: "/oauth/authorize",
    token_url: "/oauth/token"
  )

{:ok, token} =
  Pristine.OAuth2.Interactive.authorize(provider,
    client_id: "...",
    client_secret: "...",
    redirect_uri: "http://127.0.0.1:40071/callback",
    context: context
  )
```

Loopback callback capture is exact-URI only and requires a literal loopback IP
such as `127.0.0.1` or `::1`. If the redirect URI is not a supported loopback
URI, Pristine falls back to manual paste-back.

If you want durable token storage without introducing provider-specific policy
into your app code, use `Pristine.Adapters.TokenSource.File`:

```elixir
token_path = Path.expand("~/.config/example/oauth/token.json")

:ok =
  Pristine.Adapters.TokenSource.File.put(token,
    path: token_path,
    create_dirs?: true
  )

context = Pristine.context(
  auth: %{
    "bearerAuth" => [
      Pristine.Adapters.Auth.OAuth2.new(
        token_source: {Pristine.Adapters.TokenSource.File, path: token_path}
      )
    ]
  }
)
```

The file format is JSON and keeps provider-returned metadata in
`token.other_params`.

If the provider also returns expiry metadata, you can layer
`Pristine.Adapters.TokenSource.Refreshable` on top of that durable source so
refreshes are persisted back through the same boundary:

```elixir
oauth_context = Pristine.context(
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: MyApp.Finch],
  serializer: Pristine.Adapters.Serializer.JSON
)

context = Pristine.context(
  auth: %{
    "bearerAuth" => [
      Pristine.Adapters.Auth.OAuth2.new(
        token_source:
          {Pristine.Adapters.TokenSource.Refreshable,
           inner_source: {Pristine.Adapters.TokenSource.File, path: token_path},
           provider: provider,
           context: oauth_context,
           client_id: System.fetch_env!("OAUTH_CLIENT_ID"),
           client_secret: System.fetch_env!("OAUTH_CLIENT_SECRET"),
           refresh_skew_seconds: 60}
      )
    ]
  }
)
```

`Refreshable` only acts on tokens that already include `expires_at`. For
providers that do not expose expiry metadata, keep refresh explicit instead of
inventing pre-expiry policy.

### Telemetry Exporters

Emit regular `:telemetry` events from the runtime, then attach a reporter as an
exporter:

```elixir
children = [
  {Finch, name: MyApp.Finch},
  Pristine.Profiles.Foundation.reporter_child_spec(
    name: MyApp.TelemetryReporter,
    transport: MyApp.TelemetryTransport
  )
]

{:ok, handler_id} =
  Pristine.Profiles.Foundation.attach_reporter(
    context,
    reporter: MyApp.TelemetryReporter
  )
```

That keeps local handlers, metrics, and external export on the same telemetry
event stream.

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
