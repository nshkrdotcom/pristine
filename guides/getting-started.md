# Getting Started

Pristine now exposes a narrow runtime boundary for first-party SDKs:

- `Pristine.execute_request/3`
- `Pristine.foundation_context/1`
- `Pristine.SDK.*`

## 1. Build a Runtime Context

Use `Pristine.foundation_context/1` for the recommended production profile:

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [{Pristine.Adapters.Auth.Bearer, token: System.fetch_env!("API_TOKEN")}]
  )
```

If you need full manual control, use `Pristine.context/1` directly.

## 2. Execute a Request Spec

```elixir
request_spec = %{
  id: "users.get",
  method: :get,
  path: "/v1/users/{id}",
  path_params: %{"id" => "user-123"},
  query: %{"include" => "workspace"},
  headers: %{},
  body: nil,
  form_data: nil,
  auth: nil,
  security: [%{"bearerAuth" => []}],
  request_schema: nil,
  response_schema: nil,
  resource: "users",
  retry: "users.read",
  rate_limit: "users.integration",
  circuit_breaker: "core_api",
  telemetry: "request.users"
}

{:ok, response} = Pristine.execute_request(request_spec, context)
```

Request specs are the retained low-level runtime format. They carry endpoint
metadata such as `resource`, `retry`, `rate_limit`, `circuit_breaker`, and
`security` without rebuilding any manifest-shaped runtime structures.

## 3. Execute OpenAPI-Generated Request Maps

Generated SDKs usually hand `Pristine.execute_request/3` the normalized request
maps built through `Pristine.SDK.OpenAPI.*`.

```elixir
{:ok, request} =
  Pristine.SDK.OpenAPI.Client.request(%{
    args: %{"id" => "user-123"},
    call: {MySDK.Users, :get},
    method: :get,
    path_template: "/v1/users/{id}",
    path_params: %{"id" => "user-123"},
    query: %{},
    body: %{},
    form_data: %{}
  })

{:ok, response} = Pristine.execute_request(request, context)
```

## 4. Use the SDK Runtime Types

Downstream SDKs should surface the stable SDK-facing types instead of exposing
internal request-pipeline structs:

- `Pristine.SDK.Context`
- `Pristine.SDK.Response`
- `Pristine.SDK.Error`
- `Pristine.SDK.ResultClassification`
- `Pristine.SDK.OpenAPI.*`
- `Pristine.SDK.OAuth2.*`

`Pristine.SDK.OAuth2` uses the native in-tree OAuth backend by default.
Interactive browser launch and loopback callback capture stay optional adapter
layers, and manual paste-back remains available when those adapters are absent.

## Next

- Use [Foundation Runtime](foundation-runtime.md) when you need more control
  over retries, rate limiting, circuit breaking, or telemetry.
- Use [Code Generation](code-generation.md) when you are working on a
  first-party SDK generator that needs the retained OpenAPI bridge.
