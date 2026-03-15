# Testing and Verification

Related guides: `getting-started.md`, `foundation-runtime.md`,
`code-generation.md`, `oauth-and-token-sources.md`,
`manual-contexts-and-adapters.md`.

Pristine is designed so most tests can stop at the port boundary instead of
booting real HTTP stacks.

## Mock the Runtime Ports

The repo's `test/test_helper.exs` defines Mox mocks for the primary ports:

- `Pristine.TransportMock`
- `Pristine.StreamTransportMock`
- `Pristine.SerializerMock`
- `Pristine.RetryMock`
- `Pristine.TelemetryMock`
- `Pristine.AuthMock`
- `Pristine.MultipartMock`
- `Pristine.CircuitBreakerMock`
- `Pristine.RateLimitMock`

That is the intended testing seam for request execution.

## Unit Test `Pristine.execute_request/3`

The runtime tests use a manual context with mocked ports:

```elixir
context =
  Pristine.context(
    base_url: "https://api.example.com",
    transport: Pristine.TransportMock,
    serializer: Pristine.SerializerMock,
    retry: Pristine.RetryMock,
    telemetry: Pristine.TelemetryMock,
    circuit_breaker: Pristine.CircuitBreakerMock,
    rate_limiter: Pristine.RateLimitMock
  )

request_spec = %{
  id: "raw.get_user",
  method: :get,
  path: "/v1/users/{id}",
  path_params: %{"id" => "user-123"},
  query: %{"include" => "workspace"},
  headers: %{"X-Request-Source" => "raw"},
  body: nil,
  form_data: nil,
  auth: Pristine.Adapters.Auth.Bearer.new("secret-token"),
  security: nil,
  request_schema: nil,
  response_schema: nil
}
```

Then assert port interaction directly:

```elixir
expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts -> fun.() end)
expect(Pristine.CircuitBreakerMock, :call, fn "raw.get_user", fun, _opts -> fun.() end)
expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

expect(Pristine.TransportMock, :send, fn request, _context ->
  assert request.url == "https://api.example.com/v1/users/user-123?include=workspace"
  {:ok, Pristine.SDK.Response.new(status: 200, body: "{\"ok\":true}")}
end)

expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
  {:ok, %{"ok" => true}}
end)

assert {:ok, %{"ok" => true}} = Pristine.execute_request(request_spec, context)
```

This style exercises URL/path normalization, auth header shaping, retry wiring,
telemetry emission, and response decoding without crossing the real network.

## Test OAuth Flows by Injecting the Boundary

OAuth docs should be backed by the same injection points the runtime uses:

- use `Pristine.TransportMock` for control-plane HTTP exchange tests
- use `Pristine.OAuth2.SavedToken.refresh/2` with a fake `oauth2_module`
- use fake token sources to verify persisted-token merge behavior

That is how the repo tests code exchange, refresh, and saved-token rotation
without depending on a live OAuth provider.

## Verify Build-Time Output

For generator work, call `Pristine.OpenAPI.Bridge.run/3` in tests and assert on
the canonical result surface:

```elixir
result =
  Pristine.OpenAPI.Bridge.run(
    :widgets_sdk,
    ["openapi/widgets.json"],
    base_module: WidgetsSDK,
    output_dir: "lib/widgets_sdk/generated"
  )

sources = Pristine.OpenAPI.Bridge.generated_sources(result)
```

The stable verification points are:

- `%Pristine.OpenAPI.Result{}` fields such as `ir`, `source_contexts`, and
  `docs_manifest`
- generated source contents returned by
  `Pristine.OpenAPI.Bridge.generated_sources/1`
- the generated modules' request maps and schema functions after compilation

## Keep a Small Contract Test Layer

The repo already keeps a focused contract suite around the hardened boundary and
the retained build-time seam. That is a good pattern for downstream SDK repos
too.

Useful focused commands:

```bash
mix test test/pristine/docs_contract_test.exs test/pristine/streamlining_contract_test.exs
mix test test/pristine/oauth2_test.exs test/pristine/oauth2/saved_token_test.exs
mix test test/pristine/openapi/bridge_test.exs test/pristine/openapi/result_test.exs
```

Keep those contract tests narrow. They should pin the supported boundary, not
retell every implementation detail.
