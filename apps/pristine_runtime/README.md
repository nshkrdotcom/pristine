<p align="center">
  <img src="assets/pristine.svg" width="200" height="200" alt="Pristine logo" />
</p>

# Pristine

`pristine` is the published runtime package from
`apps/pristine_runtime`. It is the only package in this monorepo intended for
Hex consumption.

Use Hex for normal runtime adoption:

```elixir
{:pristine, "~> 0.2.0"}
```

The companion projects `pristine_codegen` and `pristine_provider_testkit` stay
in this repository as GitHub-sourced build-time and test-time dependencies.

## Runtime Surface

The public runtime boundary is:

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
- `Pristine.SDK.OpenAPI.Client`
- `Pristine.SDK.ProviderProfile`
- `Pristine.OAuth2`

Use `Pristine.foundation_context/1` plus `Pristine.execute_request/3` for the
recommended production path and for generated provider SDKs. Use
`Pristine.Client` plus `Pristine.Operation` when you want lower-level manual
control over operation construction and execution.

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

## Why This Package Exists

`pristine` owns the generic runtime concerns shared by provider SDKs:

- transport and streaming
- serialization and multipart handling
- auth and OAuth helpers
- retry, rate limiting, circuit breaking, and telemetry
- request path safety and response classification

Generated SDKs describe requests. `pristine` executes them.

Auth ownership stays split intentionally:

- `pristine` owns generic OAuth and token-source runtime mechanics
- provider SDKs own provider-specific helper modules and docs
- higher control planes own durable install and secret authority

## Guides

- `guides/getting-started.md`
- `guides/foundation-runtime.md`
- `guides/manual-contexts-and-adapters.md`
- `guides/oauth-and-token-sources.md`
- `guides/streaming-and-sse.md`

## Project Files

- `CHANGELOG.md`
- `LICENSE.md`
- `examples/demo.exs`

## Workspace

Workspace-wide quality commands run from the repo root:

```bash
mix mr.compile
mix mr.test
mix ci
```
