# Runtime And SDK Usage

The runtime package supports two equally important contracts:

- the low-level `Pristine.Client` plus `Pristine.Operation` flow
- the SDK-facing request-spec flow built around
  `Pristine.foundation_context/1`, `Pristine.execute_request/3`, and
  `Pristine.SDK.OpenAPI.Client`

## Recommended Production Path

Use the Foundation-backed runtime context for most real integrations:

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [{Pristine.Adapters.Auth.Bearer, token: System.fetch_env!("API_TOKEN")}]
  )

request = %{
  id: "widgets.list",
  method: :get,
  path_template: "/v1/widgets",
  query: %{"limit" => 10},
  auth: %{use_client_default?: true, override: nil, security_schemes: ["bearerAuth"]},
  resource: "widgets",
  retry: "widgets.read",
  circuit_breaker: "widgets_api",
  rate_limit: "widgets.integration",
  telemetry: [:my_sdk, :widgets, :list]
}

{:ok, response} = Pristine.execute_request(request, context)
```

This path is the best fit for generated providers because it keeps the runtime
boundary small while still preserving retry, rate limiting, telemetry, and
streaming support.

## Manual Runtime Path

Use `Pristine.Client.new/1` and `Pristine.Operation.new/1` when you need direct
control over adapters, minimal test profiles, or explicit operation rendering.

That flow is still a first-class runtime contract and remains the model that
many generated modules ultimately target.

## OAuth And Streaming

`Pristine.OAuth2` is the generic OAuth control plane. It uses the same runtime
transport boundary for authorization, token exchange, refresh, revocation, and
introspection.

`Pristine.stream/3` continues to accept the operation envelope and returns a
`Pristine.Response` whose `:stream` field can be consumed lazily. SSE support is
provided by the streaming adapters and helper modules such as
`Pristine.Streaming.SSEDecoder`.

## Where To Go Deeper

- runtime package overview: `apps/pristine_runtime/README.md`
- runtime guides in `apps/pristine_runtime/guides/*.md`
- [Runtime Internals](runtime-internals.md) for the pipeline and adapter model
