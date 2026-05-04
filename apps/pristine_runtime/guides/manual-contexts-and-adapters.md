# Manual Contexts And Adapters

`Pristine.Client.new/1` gives direct control over the runtime ports and adapters
without going through the curated Foundation profile.

For the covered unary lane, `Pristine.Adapters.Transport.Finch` keeps its
compatibility module name but no longer owns raw HTTP execution. It emits
`HttpExecutionIntent.v1` and delegates the lower request/response hop to
`execution_plane`, while `Pristine.Adapters.Transport.FinchStream` remains the
stream transport path.

## Manual Client Wiring

This direct wiring example is standalone compatibility. Env-backed
`default_auth`, direct `base_url`, and `default_headers` are rejected when a
governed authority is attached.

```elixir
client =
  Pristine.Client.new(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    stream_transport: Pristine.Adapters.Transport.FinchStream,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    retry: Pristine.Adapters.Retry.Noop,
    rate_limiter: Pristine.Adapters.RateLimit.Noop,
    circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
    telemetry: Pristine.Adapters.Telemetry.Noop,
    default_headers: %{"x-client" => "manual"},
    default_auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
  )
```

Governed manual wiring supplies the authority value and adapter choices only:

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

client =
  Pristine.Client.new(
    governed_authority: authority,
    transport: Pristine.Adapters.Transport.Finch,
    stream_transport: Pristine.Adapters.Transport.FinchStream,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    retry: Pristine.Adapters.Retry.Noop,
    rate_limiter: Pristine.Adapters.RateLimit.Noop,
    circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
    telemetry: Pristine.Adapters.Telemetry.Noop
  )
```

## Direct Execution

```elixir
operation =
  Pristine.Operation.new(%{
    id: "widgets.list",
    method: :get,
    path_template: "/v1/widgets",
    query: %{"limit" => 10},
    response_schemas: %{200 => nil},
    auth: %{
      use_client_default?: true,
      override: nil,
      security_schemes: ["bearerAuth"]
    },
    runtime: %{
      resource: "widgets",
      retry_group: "widgets.read",
      circuit_breaker: "widgets_api",
      rate_limit_group: "widgets.integration",
      telemetry_event: [:my_sdk, :widgets, :list],
      timeout_ms: nil
    }
  })

{:ok, data} = Pristine.execute(client, operation)
```

## When To Use Manual Wiring

Prefer `Pristine.Client.new/1` when you need to:

- override adapters directly
- supply custom retry, auth, or telemetry implementations
- run a minimal local or test profile
- configure both request and stream transports explicitly
