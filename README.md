# Pristine

Pristine is the shared runtime substrate for first-party OpenAPI-based Elixir
SDKs.

The retained public runtime boundary is:

- `Pristine.execute_request/3`
- `Pristine.foundation_context/1`
- `Pristine.SDK.*`

The retained build-time seam is `Pristine.OpenAPI.Bridge.run/3`.

## Runtime Boundary

Provider SDKs should depend on the hardened boundary above instead of reaching
into `Pristine.Core.*` or `Pristine.OpenAPI.*` internals directly.

Use `Pristine.foundation_context/1` for the recommended production runtime:

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

Execute a normalized request spec through `Pristine.execute_request/3`:

```elixir
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
  response_schema: nil,
  resource: "widgets",
  retry: "widgets.read",
  rate_limit: "widgets.integration",
  circuit_breaker: "core_api",
  telemetry: "request.widgets"
}

{:ok, response} = Pristine.execute_request(request_spec, context)
```

`Pristine.SDK.*` exposes the stable runtime-facing types used by downstream SDKs:

- `Pristine.SDK.Context`
- `Pristine.SDK.Response`
- `Pristine.SDK.Error`
- `Pristine.SDK.ResultClassification`
- `Pristine.SDK.OpenAPI.*`
- `Pristine.SDK.OAuth2.*`
- `Pristine.SDK.Profiles.Foundation`

## OAuth Provider Construction

SDK-facing OAuth provider construction stays tied to OpenAPI security scheme
metadata, not to manifests.

```elixir
provider =
  Pristine.SDK.OAuth2.Provider.from_security_scheme!(
    "notionOAuth",
    %{
      "type" => "oauth2",
      "flows" => %{
        "authorizationCode" => %{
          "authorizationUrl" => "/v1/oauth/authorize",
          "tokenUrl" => "/v1/oauth/token",
          "scopes" => %{"workspace.read" => "Read workspace data"}
        }
      },
      "x-pristine-flow" => "authorizationCode",
      "x-pristine-token-content-type" => "application/json"
    },
    site: "https://api.notion.com"
  )
```

## Build-Time Bridge

`Pristine.OpenAPI.Bridge.run/3` is the retained first-party build-time seam for
SDK generation. It is not the normal consumer runtime entry.

```elixir
result =
  Pristine.OpenAPI.Bridge.run(
    :notion_sdk,
    ["openapi/notion.json"],
    source_contexts: %{}
  )

sources = Pristine.OpenAPI.Bridge.generated_sources(result)
```

## OAuth Runtime Architecture

`Pristine.SDK.OAuth2` now runs through the in-tree
`Pristine.Adapters.OAuthBackend.Native` backend by default.

Interactive convenience features remain optional adapters:

- browser launch via `Pristine.Adapters.OAuthBrowser.SystemCmd`
- loopback callback capture via `Pristine.Adapters.OAuthCallbackListener.Bandit`

Manual paste-back still works without those adapters, and persisted token
load/save/refresh orchestration lives in `Pristine.OAuth2.SavedToken` on top of
the token-source port.

## Guides

- [Getting Started](guides/getting-started.md)
- [Foundation Runtime](guides/foundation-runtime.md)
- [Code Generation](guides/code-generation.md)
