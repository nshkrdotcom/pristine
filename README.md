<p align="center">
  <img src="assets/pristine.svg" width="200" height="200" alt="Pristine logo" />
</p>

<h1 align="center">Pristine</h1>

<p align="center">
  <a href="https://hex.pm/packages/pristine"><img src="https://img.shields.io/hexpm/v/pristine.svg" alt="Hex Version" /></a>
  <a href="https://hexdocs.pm/pristine"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs" /></a>
  <a href="https://github.com/nshkrdotcom/pristine"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License" /></a>
</p>

Pristine is the shared runtime and build-time bridge for first-party
OpenAPI-based Elixir SDKs.

The recommended provider-SDK boundary is:

- `Pristine.execute_request/3`
- `Pristine.foundation_context/1`
- `Pristine.SDK.*`

The retained build-time seam is `Pristine.OpenAPI.Bridge.run/3`.

`Pristine.context/1` also remains available when you want full manual
ports-and-adapters control, but provider SDKs should treat `Pristine.Core.*`
and `Pristine.OpenAPI.*` as internal implementation detail rather than as the
blessed SDK contract.

## Runtime Boundary

Use `Pristine.foundation_context/1` for the recommended production runtime:

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
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

`Pristine.execute_request/3` also accepts the generated request maps emitted by
`Pristine.SDK.OpenAPI.Client`. In both cases, the same runtime path validation,
serialization, auth, retry, telemetry, rate-limit, and circuit-breaker wiring
still applies.

`Pristine.SDK.*` exposes the stable runtime-facing types used by downstream SDKs:

- `Pristine.SDK.Context`
- `Pristine.SDK.Response`
- `Pristine.SDK.Error`
- `Pristine.SDK.ResultClassification`
- `Pristine.SDK.OpenAPI.*`
- `Pristine.SDK.OAuth2.*`
- `Pristine.SDK.Profiles.Foundation`

## Manual Context Construction

Use `Pristine.context/1` when you want complete control over the raw runtime
ports and adapters:

```elixir
context =
  Pristine.context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    retry: Pristine.Adapters.Retry.Noop,
    telemetry: Pristine.Adapters.Telemetry.Noop
  )
```

That lower-level constructor is useful for bespoke clients and tests. The
Foundation profile exists so production callers do not have to hand-wire the
same resilience and telemetry stack repeatedly.

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

`Pristine.SDK.OAuth2` uses the in-tree
`Pristine.Adapters.OAuthBackend.Native` backend by default. Browser launch and
loopback callback capture stay optional adapter seams:

- `Pristine.Adapters.OAuthBrowser.SystemCmd`
- `Pristine.Adapters.OAuthCallbackListener.Bandit`

Manual paste-back still works without those adapters, and persisted token
load/save/refresh orchestration lives in `Pristine.OAuth2.SavedToken` on top of
the token-source boundary.

## Build-Time Bridge

`Pristine.OpenAPI.Bridge.run/3` is the retained first-party build-time seam for
SDK generation. It is not the normal consumer runtime entry.

The bridge needs at least a base module and output directory:

```elixir
result =
  Pristine.OpenAPI.Bridge.run(
    :widgets_sdk,
    ["openapi/widgets.json"],
    base_module: WidgetsSDK,
    output_dir: "lib/widgets_sdk/generated",
    source_contexts: %{
      {:get, "/v1/widgets"} => %{
        title: "Widgets",
        url: "https://docs.example.com/widgets"
      }
    }
  )

sources = Pristine.OpenAPI.Bridge.generated_sources(result)
```

The returned `%Pristine.OpenAPI.Result{}` contains:

- `ir`
- `source_contexts`
- `docs_manifest`

That lets first-party SDK generators reuse the same IR, generated files, and
docs manifest without exposing a manifest-shaped runtime API.

## Guides

- [Getting Started](guides/getting-started.md)
- [Foundation Runtime](guides/foundation-runtime.md)
- [Manual Contexts and Adapters](guides/manual-contexts-and-adapters.md)
- [OAuth and Token Sources](guides/oauth-and-token-sources.md)
- [Streaming and SSE](guides/streaming-and-sse.md)
- [Code Generation](guides/code-generation.md)
- [Testing and Verification](guides/testing-and-verification.md)
