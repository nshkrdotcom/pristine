# Getting Started

Pristine exposes a small runtime boundary for generated providers and thin
provider facades:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.context/1`
- `Pristine.foundation_context/1`
- `Pristine.execute/3`
- `Pristine.execute_request/3`
- `Pristine.stream/3`
- `Pristine.SDK.OpenAPI.Client`
- `Pristine.OAuth2`

## 1. Build A Runtime Client

Use `Pristine.foundation_context/1` for the recommended production profile:

This first example is standalone direct use. Reading `API_TOKEN` before
building the context is compatible for direct providers, but it is not governed
authority.

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

For governed execution, pass only an authority-materialized value for the
credential and target.

```elixir
authority =
  Pristine.GovernedAuthority.new!(
    base_url: "https://api.example.com",
    base_url_ref: "base-url://example/workspace-123",
    credential_handle_ref: "credential-handle://example/workspace-123",
    credential_lease_ref: "credential-lease://example/one-effect",
    target_ref: "target://example/production",
    request_scope_ref: "request-scope://example/widgets/list",
    header_policy_ref: "header-policy://example/default",
    materialization_kind: "bearer",
    bearer_token_ref: "bearer-token://example/one-effect",
    redaction_ref: "redaction://headers",
    headers: %{"x-authority-target" => "target://example/production"},
    credential_headers: %{"authorization" => "Bearer authority-materialized-token"},
    allowed_header_names: ["authorization", "x-authority-target"]
  )

context =
  Pristine.foundation_context(
    governed_authority: authority,
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON
  )
```

## 2. Build A Request Spec Or Operation

Generated providers now emit request maps and call `Pristine.execute_request/3`
through their thin client facade. The lower-level `Pristine.Operation` path is
still available when you need to assemble operations by hand.

```elixir
request = %{
  id: "users.get",
  method: :get,
  path_template: "/v1/users/{id}",
  path_params: %{"id" => "user-123"},
  query: %{"include" => "workspace"},
  auth: %{use_client_default?: true, override: nil, security_schemes: ["bearerAuth"]},
  resource: "users",
  retry: "users.read",
  circuit_breaker: "users_api",
  rate_limit: "users.integration",
  telemetry: [:my_sdk, :users, :get]
}
```

## 3. Execute Or Stream

```elixir
{:ok, data} = Pristine.execute_request(request, context)
```

For unary request/response execution, the default Finch-named adapter now emits
`HttpExecutionIntent.v1` and delegates the lower HTTP hop to
`execution_plane`. `Pristine.stream/3` remains the stream-oriented path and
keeps using the explicit stream transport adapter.

`Pristine.stream/3` still consumes the lower-level `Pristine.Operation`
envelope. The stream transport returns a `Pristine.Response` whose `:stream`
field is enumerable.

## 4. Generated Wrapper Helpers

Generated operation modules can keep their rendering logic small by using
`Pristine.SDK.OpenAPI.Client.partition/2`,
`Pristine.SDK.OpenAPI.Client.items/2`, and
`Pristine.SDK.OpenAPI.Client.next_page_request/2`.

## Next

- Use [Foundation Runtime](foundation-runtime.md) when you want the curated
  production profile plus telemetry reporter helpers.
- Use [Manual Contexts And Adapters](manual-contexts-and-adapters.md) when you
  need to wire ports and adapters directly.
- Use [OAuth And Token Sources](oauth-and-token-sources.md) for control-plane
  OAuth flows.
