# Pristine Runtime

`apps/pristine_runtime` publishes the `pristine` runtime package.

The public runtime contract is:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.Response`
- `Pristine.Error`
- `Pristine.execute/3`
- `Pristine.stream/3`
- `Pristine.OAuth2`

## Example

```elixir
client =
  Pristine.Client.foundation(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    default_auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
  )

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

{:ok, response} = Pristine.execute(client, operation)
```

## Guides

- `guides/getting-started.md`
- `guides/foundation-runtime.md`
- `guides/manual-contexts-and-adapters.md`
- `guides/oauth-and-token-sources.md`
- `guides/streaming-and-sse.md`

## Workspace

Workspace-wide quality commands run from the repo root:

```bash
mix mr.compile
mix mr.test
mix ci
```
