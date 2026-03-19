# Pristine Runtime

`apps/pristine_runtime` is the publishable `pristine` package.

The current runtime-facing surface remains:

- `Pristine.execute_request/3`
- `Pristine.foundation_context/1`
- `Pristine.context/1`
- `Pristine.SDK.*`

## Example

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
  )

request_spec = %{
  id: "widgets.list",
  method: :get,
  path: "/v1/widgets",
  path_params: %{},
  query: %{"limit" => 10},
  headers: %{},
  body: nil,
  form_data: nil,
  auth: nil,
  security: [%{"bearerAuth" => []}],
  request_schema: nil,
  response_schema: nil
}

{:ok, response} = Pristine.execute_request(request_spec, context)
```

Generated SDKs still compile against `Pristine.SDK.*` and the runtime OpenAPI
helpers carried by this package.

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
