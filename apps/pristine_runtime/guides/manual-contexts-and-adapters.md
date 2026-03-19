# Manual Contexts and Adapters

Related guides: `getting-started.md`, `foundation-runtime.md`,
`oauth-and-token-sources.md`, `streaming-and-sse.md`,
`testing-and-verification.md`.

Use `Pristine.context/1` when you want direct control over the runtime ports
and adapters instead of the curated Foundation profile.

`Pristine.foundation_context/1` remains the recommended production default. This
guide is for SDK authors and advanced consumers who need to wire the runtime by
hand.

## Build a Fully Manual Context

```elixir
context =
  Pristine.context(
    base_url: "https://api.example.com",
    headers: %{"X-Client" => "widgets-sdk"},
    default_query: %{"locale" => "en-US"},
    default_timeout: 15_000,
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    multipart: Pristine.Adapters.Multipart.Ex,
    auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))],
    retry: Pristine.Adapters.Retry.Noop,
    telemetry: Pristine.Adapters.Telemetry.Noop
  )
```

That context can execute the same request specs and generated request maps that
the Foundation profile handles:

```elixir
{:ok, response} = Pristine.execute_request(request_spec, context)
```

## Common Auth Adapters

`Pristine.context/1` accepts a list of auth adapter tuples under `:auth`.

Bearer:

```elixir
Pristine.Adapters.Auth.Bearer.new("secret-token")
```

API key:

```elixir
Pristine.Adapters.Auth.ApiKey.new("key-123", header: "X-API-Key")
```

Basic:

```elixir
Pristine.Adapters.Auth.Basic.new("client-id", "client-secret")
```

OAuth-backed bearer auth from a token source:

```elixir
Pristine.Adapters.Auth.OAuth2.new(
  token_source: {Pristine.Adapters.TokenSource.File, path: "/tmp/oauth.json"}
)
```

The OAuth2 auth adapter fails clearly when the token source is missing, the
saved token has no access token, or the token is expired. Pass
`allow_stale?: true` only when you intentionally want to bypass the expiry
check.

## Useful Runtime Seams

The raw context keeps a wider set of composition points available:

- `transport` and `transport_opts`
- `serializer`
- `multipart` and `multipart_opts`
- `retry` and `retry_opts`
- `result_classifier`
- `telemetry`, `telemetry_events`, and `telemetry_metadata`
- `headers`, `default_query`, and `default_timeout`
- `type_schemas` for runtime schema resolution
- `error_module` and `response_wrapper`
- `logger`, `log_level`, `dump_headers?`, `redact_headers`, and `extra_headers`
- `pool_manager` and `pool_base`
- `stream_transport` and `streaming` for callers that keep direct streaming
  adapters in the same context

That makes `Pristine.context/1` useful for:

- provider SDKs with unusual auth composition
- test contexts that deliberately swap one adapter at a time
- custom retry or telemetry behavior outside the Foundation profile
- stream-capable clients that want to carry streaming adapters alongside normal
  request execution state

## Generated SDKs Still Use the Same Boundary

Manual contexts do not change the public request contract. Generated SDKs should
still hand the runtime:

- normalized request specs
- generated request maps from `Pristine.SDK.OpenAPI.Client`

The point of a manual context is adapter control, not a different execution
API.

## When to Stay on Foundation

Prefer `Pristine.foundation_context/1` when you want:

- a ready-made retry/rate-limit/circuit-breaker stack
- default telemetry event naming
- Foundation-backed admission control
- less repeated wiring across multiple SDK clients

Drop to `Pristine.context/1` when the Foundation profile is too opinionated for
the integration you are building.
