# Runtime And SDK Usage

The runtime package supports two equally important contracts:

- the low-level `Pristine.Client` plus `Pristine.Operation` flow
- the SDK-facing request-spec flow built around
  `Pristine.foundation_context/1`, `Pristine.execute_request/3`, and
  `Pristine.SDK.OpenAPI.Client`

## Recommended Standalone Production Path

This direct context shape is standalone compatibility. A provider facade may
read env or local config before constructing this context for direct use, but
those values are not governed authority.

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

## Governed Production Path

Governed mode starts only from a `Pristine.GovernedAuthority` value produced by
the selected authority materializer. Pristine rejects direct base URLs, direct
headers, direct auth adapters, request auth overrides, request headers, and
OAuth saved-token sources while that value is attached.

```elixir
authority =
  Pristine.GovernedAuthority.new!(
    base_url: "https://api.example.com",
    base_url_ref: "base-url://example/workspace-123",
    credential_handle_ref: "credential-handle://example/workspace-123",
    credential_lease_ref: "credential-lease://example/one-effect",
    target_ref: "target://example/production",
    request_scope_ref: "request-scope://example/widgets/list",
    header_policy_ref: "header-policy://example/default",
    materialization_kind: "bearer",
    bearer_token_ref: "bearer-token://example/one-effect",
    redaction_ref: "redaction://headers",
    headers: %{"x-authority-target" => "target://example/production"},
    credential_headers: %{"authorization" => "Bearer authority-materialized-token"},
    allowed_header_names: ["authorization", "x-authority-target"]
  )

context =
  Pristine.foundation_context(
    governed_authority: authority,
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON
  )

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
