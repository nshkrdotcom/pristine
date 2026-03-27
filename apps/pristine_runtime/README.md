# Pristine Runtime

`apps/pristine_runtime` publishes the `pristine` runtime package.

Consumer repos should depend on this child app directly. In local development,
that typically means `{:pristine, path: "../pristine/apps/pristine_runtime"}`.
If a sibling checkout is not available, use a GitHub fallback with
`subdir: "apps/pristine_runtime"` instead of vendoring another copy of the
workspace into committed `deps/`.

The public runtime contract is:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.context/1`
- `Pristine.foundation_context/1`
- `Pristine.Response`
- `Pristine.Error`
- `Pristine.execute/3`
- `Pristine.execute_request/3`
- `Pristine.stream/3`
- `Pristine.SDK.*`
- `Pristine.OAuth2`

`Pristine.Client` / `Pristine.Operation` remain the low-level manual contract.
First-party provider SDKs now target the lighter request-spec boundary built
from `Pristine.foundation_context/1`, `Pristine.execute_request/3`, and
`Pristine.SDK.OpenAPI.Client`.

## Example

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
