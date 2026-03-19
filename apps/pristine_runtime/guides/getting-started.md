# Getting Started

Pristine exposes a small runtime boundary for generated providers and thin
provider facades:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.execute/3`
- `Pristine.stream/3`
- `Pristine.OAuth2`

## 1. Build A Runtime Client

Use `Pristine.Client.foundation/1` for the recommended production profile:

```elixir
client =
  Pristine.Client.foundation(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    default_auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
  )
```

## 2. Render A Runtime Operation

Generated providers render a `Pristine.Operation` and call the runtime
directly.

```elixir
operation =
  Pristine.Operation.new(%{
    id: "users.get",
    method: :get,
    path_template: "/v1/users/{id}",
    path_params: %{"id" => "user-123"},
    query: %{"include" => "workspace"},
    response_schemas: %{200 => nil},
    auth: %{
      use_client_default?: true,
      override: nil,
      security_schemes: ["bearerAuth"]
    },
    runtime: %{
      resource: "users",
      retry_group: "users.read",
      circuit_breaker: "users_api",
      rate_limit_group: "users.integration",
      telemetry_event: [:my_sdk, :users, :get],
      timeout_ms: nil
    }
  })
```

## 3. Execute Or Stream

```elixir
{:ok, data} = Pristine.execute(client, operation)
```

`Pristine.stream/3` consumes the same `Pristine.Operation` envelope. The stream
transport returns a `Pristine.Response` whose `:stream` field is enumerable.

## 4. Generated Wrapper Helpers

Generated operation modules can keep their rendering logic small by using
`Pristine.Operation.partition/2`, `Pristine.Operation.render_path/2`,
`Pristine.Operation.items/2`, and `Pristine.Operation.next_page/2`.

## Next

- Use [Foundation Runtime](foundation-runtime.md) when you want the curated
  production profile plus telemetry reporter helpers.
- Use [Manual Contexts And Adapters](manual-contexts-and-adapters.md) when you
  need to wire ports and adapters directly.
- Use [OAuth And Token Sources](oauth-and-token-sources.md) for control-plane
  OAuth flows.
