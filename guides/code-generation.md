# Code Generation

`Pristine.OpenAPI.Bridge.run/3` is the retained first-party build-time seam for
provider SDK generation.

It is intentionally separate from the runtime consumer surface:

- runtime consumers use `Pristine.execute_request/3`
- SDKs build contexts through `Pristine.foundation_context/1`
- SDK-facing types live under `Pristine.SDK.*`
- `Pristine.OpenAPI.Bridge.run/3` is for first-party build-time generation
- It is not the normal consumer runtime entry

`Pristine.OpenAPI.Bridge.run/3` also requires `oapi_generator` to be present as
a build-time dependency.

## Running the Bridge

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

The bridge result is a `%Pristine.OpenAPI.Result{}` that retains the shared
build artifacts needed by first-party SDK generators:

- `ir`
- `source_contexts`
- `docs_manifest`

The generated source files themselves still come from the configured
`output_dir`, and `Pristine.OpenAPI.Bridge.generated_sources/1` lets you read
those rendered files back for verification.

## Runtime Contract for Generated SDKs

Generated SDKs should target the hardened runtime boundary instead of any
manifest-first API:

- `Pristine.execute_request/3`
- `Pristine.foundation_context/1`
- `Pristine.SDK.*`

In practice that means generated providers should lean on:

- `Pristine.SDK.OpenAPI.Client`
- `Pristine.SDK.OpenAPI.Operation`
- `Pristine.SDK.OpenAPI.Runtime`
- `Pristine.SDK.OAuth2.*`

That keeps generated packages isolated from `Pristine.Core.*` and other runtime
internals.

## OAuth Security Scheme Metadata

SDK-facing OAuth provider construction comes from OpenAPI security scheme data:

```elixir
provider =
  Pristine.SDK.OAuth2.Provider.from_security_scheme!(
    "providerOAuth",
    %{
      "type" => "oauth2",
      "flows" => %{
        "authorizationCode" => %{
          "authorizationUrl" => "/oauth/authorize",
          "tokenUrl" => "/oauth/token",
          "scopes" => %{"user.read" => "Read users"}
        }
      },
      "x-pristine-flow" => "authorizationCode",
      "x-pristine-default-scopes" => ["user.read"],
      "x-pristine-client-auth-method" => "request_body",
      "x-pristine-token-method" => "post",
      "x-pristine-token-content-type" => "application/json",
      "x-pristine-revocation-url" => "/oauth/revoke",
      "x-pristine-introspection-url" => "/oauth/introspect"
    },
    site: "https://api.example.com"
  )
```

The retained `x-pristine-*` extensions are:

- `x-pristine-flow`
- `x-pristine-default-scopes`
- `x-pristine-client-auth-method`
- `x-pristine-token-method`
- `x-pristine-token-content-type`
- `x-pristine-revocation-url`
- `x-pristine-introspection-url`

These extensions let first-party SDK generators preserve provider-specific OAuth
behavior without exposing manifests through the blessed SDK namespace.

At runtime, generated SDKs use `Pristine.SDK.OAuth2` against Pristine's native
default OAuth backend. Browser launch and loopback callback capture stay
optional adapter layers for SDKs that offer interactive onboarding flows.
