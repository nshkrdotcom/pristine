# Manual Contexts And Adapters

`Pristine.Client.new/1` gives direct control over the runtime ports and adapters
without going through the curated Foundation profile.

## Manual Client Wiring

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
