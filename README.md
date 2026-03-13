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
- **Optional OAuth2 Control Plane** — Authorization URL generation, PKCE, token exchange, refresh, revoke, and introspect helpers without routing normal API traffic through Tesla
- **Resilience Built-In** — Classifier-driven retries, circuit breakers, shared rate limiting, and optional admission control
- **Streaming Support** — First-class SSE (Server-Sent Events) handling
- **Observable** — Telemetry events throughout the request lifecycle
- **Production Profile** — Shared Foundation-backed runtime wiring through `Pristine.foundation_context/1`
- **Extensible** — Swap adapters for transport, auth, serialization, and more

## Installation

Add Pristine to your dependencies:

```elixir
def deps do
  [
    {:pristine, "~> 0.1.0"},
    {:oauth2, "~> 2.1"} # Only if you want Pristine.OAuth2 helpers
  ]
end
```

`oauth2` stays optional. Pristine's normal runtime and generated SDK execution path do not depend on Tesla or the `oauth2` request client.

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
resource = MyAPI.Client.users(client)
{:ok, user} = MyAPI.Users.get(resource, "user-123")
{:ok, new_user} = MyAPI.Users.create(resource, "John Doe", email: "john@example.com")
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
| **Result Classifier** | HTTP |
| **Circuit Breaker** | Foundation, Noop |
| **Rate Limit** | BackoffWindow, Noop |
| **Admission Control** | Dispatch, Noop |
| **Telemetry** | Foundation, Raw, Reporter, Noop |
| **Compression** | Gzip |
| **TokenSource** | File, Refreshable, Static |
| **Streaming** | SSE |

## Runtime Execution

Execute endpoints without code generation:

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
  rate_limit: [key: {:my_app, :my_api}, registry: MyApp.RateLimits],
  circuit_breaker: [registry: MyApp.Breakers],
  telemetry: [namespace: [:my_api], metadata: %{service: :my_api}]
)

# Execute endpoint
{:ok, result} = Pristine.execute(manifest, :get_user, %{}, context,
  path_params: %{"id" => "123"}
)
```

For low-level escape-hatch requests, use `Pristine.execute_request/3` instead of
rebuilding custom transport logic in each generated SDK:

```elixir
request_spec = %{
  method: :get,
  path: "/users/{id}",
  path_params: %{"id" => "123"},
  query: %{"include" => "profile"},
  body: nil,
  form_data: nil,
  headers: %{"X-Trace-ID" => "req-123"},
  auth: "your-token",
  security: nil,
  request_schema: nil,
  response_schema: nil,
  id: "raw.get_user"
}

{:ok, result} = Pristine.execute_request(request_spec, context)
```

`Pristine.execute_request/3` and `Pristine.execute/5` share the same request
pipeline, including request-path and path-param traversal validation. Generated
SDKs should wrap this API instead of inventing their own raw-request execution
path.

`Pristine.foundation_context/1` is the recommended production entry point. It
builds a cohesive runtime over the existing ports/adapters surface:

- Foundation-backed retry with a default two-attempt policy
- shared rate-limit learning via `Pristine.Adapters.RateLimit.BackoffWindow`
- Foundation circuit breaking
- structured telemetry events under `[:pristine, ...]` or your namespace
- optional Dispatch-backed admission control

`Pristine.context/1` remains the low-level escape hatch when you need to wire
every seam manually.

HTTP resilience behavior is classifier-driven. `result_classifier` decides:

- whether a result is retryable
- whether a shared limiter should learn a backoff window
- whether the circuit breaker should record success, failure, or ignore the outcome
- which classification metadata should be attached to telemetry

SDKs can replace `Pristine.Adapters.ResultClassifier.HTTP` with provider-specific
classification while keeping the rest of the runtime generic.

If you need high-throughput shaping, `admission_control` wraps the request path
outside the transport call. This is where adapters such as
`Pristine.Adapters.AdmissionControl.Dispatch` can coordinate `Foundation.Dispatch`
with classified backoff signals.

When you enable that adapter, pass a real `Foundation.Dispatch` server handle
through `admission_opts`. Registered names are supported, and invalid explicit
dispatch config raises instead of silently falling back to noop behavior.

## Telemetry Export

Use normal `:telemetry` emission in the runtime, then attach
`TelemetryReporter` as an exporter:

```elixir
children = [
  {Finch, name: MyApp.Finch},
  Pristine.Profiles.Foundation.reporter_child_spec(
    name: MyApp.TelemetryReporter,
    transport: MyApp.TelemetryTransport
  )
]

context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch]
  )

{:ok, handler_id} =
  Pristine.Profiles.Foundation.attach_reporter(
    context,
    reporter: MyApp.TelemetryReporter
  )
```

This is the preferred export path for new code. The legacy
`Pristine.Adapters.Telemetry.Reporter` adapter still exists as a direct
compatibility layer, but it bypasses the normal `:telemetry` handler model.

## Security Metadata And OAuth2

Pristine manifests and OpenAPI-generated request maps now carry native security metadata:

- manifest-level `security_schemes`
- manifest-level `security`
- endpoint-level `security`

At runtime the pipeline resolves auth in this order:

1. request-level `auth` override
2. endpoint `security`
3. manifest `security`
4. legacy endpoint `auth`
5. legacy context `auth`

`endpoint.security == []` explicitly disables inherited auth.

OpenAPI-generated operation request maps preserve effective security metadata
through the normal generator path. `Pristine.OpenAPI.Security.read/1` remains
available only as an explicit fallback when a caller needs to inject security
metadata manually.

`Pristine.OpenAPI.Bridge.run/3` returns a canonical
`%Pristine.OpenAPI.Result{}`. The legacy top-level `files`, `operations`, and
`schemas` fields remain in place, and the result also exposes `ir`,
`source_contexts`, `generator_state`, and a JSON-ready `docs_manifest` built by
`Pristine.OpenAPI.Docs`.

For OAuth2 control-plane work, use `Pristine.OAuth2` with a normal Pristine `Context`:

```elixir
provider =
  Pristine.OAuth2.Provider.new(
    name: "example",
    site: "https://api.example.com",
    authorize_url: "/oauth/authorize",
    token_url: "/oauth/token",
    client_auth_method: :basic,
    token_content_type: "application/json"
  )

{:ok, request} =
  Pristine.OAuth2.authorization_request(provider,
    client_id: "...",
    redirect_uri: "https://example.com/callback",
    generate_state: true,
    pkce: true,
    params: [audience: "api"]
  )

{:ok, token} =
  Pristine.OAuth2.exchange_code(provider, "code-from-callback",
    client_id: "...",
    client_secret: "...",
    redirect_uri: "https://example.com/callback",
    context: context
  )
```

For interactive terminal onboarding, use the reusable `Pristine.OAuth2`
helpers instead of rebuilding browser launch, callback capture, and manual
paste-back yourself:

```elixir
{:ok, token} =
  Pristine.OAuth2.Interactive.authorize(provider,
    client_id: "...",
    client_secret: "...",
    redirect_uri: "http://127.0.0.1:40071/callback",
    context: context
  )
```

`Pristine.OAuth2.Browser` opens the authorization URL on a best-effort basis.
`Pristine.OAuth2.CallbackServer` only binds exact literal-loopback `http`
redirect URIs such as `http://127.0.0.1:40071/callback`. Manual paste-back of
the full redirect URL or raw code is always available.

Persist tokens generically with the file-backed token source when a caller
wants JSON storage outside of any provider-specific SDK:

```elixir
token_path = Path.expand("~/.config/example/oauth/token.json")

:ok =
  Pristine.Adapters.TokenSource.File.put(token,
    path: token_path,
    create_dirs?: true
  )

{:ok, persisted_token} =
  Pristine.Adapters.TokenSource.File.fetch(path: token_path)
```

The stored envelope stays generic and round-trips `access_token`,
`refresh_token`, `expires_at`, `token_type`, and any provider metadata inside
`other_params`.

If a provider returns real expiry metadata such as `expires_at` or
`expires_in`, wrap the durable source with
`Pristine.Adapters.TokenSource.Refreshable` to refresh and persist replacements
through the same storage boundary:

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

`Refreshable` only refreshes when the token already carries real expiry data. It
does not invent expiry policy for providers that omit `expires_at`.

If your manifest already defines an OAuth2 security scheme, build the provider from that metadata instead of duplicating it in code:

```elixir
provider = Pristine.OAuth2.Provider.from_manifest!(manifest, :exampleOauth)
```

Supported scheme extensions include:

- `x-pristine-flow` to select a specific flow when the scheme defines more than one
- `x-pristine-client-auth-method` for `:basic`, `:request_body`, or `:none`
- `x-pristine-token-method` for `:post` or `:get`
- `x-pristine-token-content-type` for JSON vs form-encoded token/control requests
- `x-pristine-revocation-url`, `x-pristine-introspection-url`, and `x-pristine-default-scopes`

## OpenAPI Runtime Contract

Pristine also supports OpenAPI-generated schema refs directly at runtime. Endpoint `request` and `response` entries can point at:

- manifest-native string keys such as `"User"`
- direct type specs
- direct OpenAPI refs such as `{MySDK.User, :t}`

Generated OpenAPI schema modules are expected to expose runtime helpers:

- `__schema__/1` for validation
- `decode/1` or `decode/2` for materialization

When an SDK opts into `typed_responses: true`, successful responses are materialized through those helpers. Default runtime behavior stays compatibility-friendly: validated maps when schema refs are present, or raw decoded maps when the SDK chooses not to wire typed refs into the manifest. Broken direct refs now fail fast instead of silently skipping validation.

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
