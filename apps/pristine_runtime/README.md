<p align="center">
  <img src="assets/pristine.svg" width="200" height="200" alt="Pristine logo" />
</p>

# Pristine

`pristine` is the published runtime package from
`apps/pristine_runtime`. It is the only package in this monorepo intended for
Hex consumption.

Use Hex for normal runtime adoption:

```elixir
{:pristine, "~> 0.4.0"}
```

The companion projects `pristine_codegen` and `pristine_provider_testkit` stay
in this repository as GitHub-sourced build-time and test-time dependencies.

## Runtime Surface

The public runtime boundary is:

- `Pristine.Client`
- `Pristine.Operation`
- `Pristine.GovernedAuthority`
- `Pristine.GovernedOperationDescriptor`
- `Pristine.context/1`
- `Pristine.foundation_context/1`
- `Pristine.Response`
- `Pristine.Error`
- `Pristine.Cancellation`
- `Pristine.RuntimeCapabilities`
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

For the covered Wave 3 unary lane, `Pristine.Adapters.Transport.Finch` remains
the compatibility-named request adapter but now emits `HttpExecutionIntent.v1`
and delegates raw request/response execution to `execution_plane`. `pristine`
still owns request shaping, auth, retries, telemetry, normalized responses, and
the transport-versus-semantic failure boundary. Streaming and SSE remain on the
explicit stream transport lane.

## Standalone Example

Standalone direct use may still pass explicitly loaded local development
credentials before constructing a Pristine context. Those values are direct
runtime inputs only and do not satisfy governed authority.

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [{Pristine.Adapters.Auth.Bearer, token: load_local_development_token()}]
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

## Governed Operation Descriptor

`Pristine.GovernedOperationDescriptor` is a standalone-safe ref descriptor for
OpenAPI operations that will be admitted by an owning control plane. It covers
tool tasks, eval dataset loaders, generated SDKs, and AppKit management APIs
without adding a Jido, Citadel, Mezzanine, or AppKit dependency to Pristine.

```elixir
descriptor =
  Pristine.GovernedOperationDescriptor.new!(
    operation_ref: "pristine-operation://github/issues/list",
    connector_admission_ref: "connector-admission://tenant-1/github",
    provider_account_ref: "provider-account://tenant-1/github/app",
    credential_lease_ref: "credential-lease://tenant-1/github/app",
    operation_policy_ref: "operation-policy://tenant-1/github/issues/list",
    tenant_ref: "tenant://tenant-1",
    subject_ref: "subject://tenant-1/operator/ada",
    trace_ref: "trace://tenant-1/github/issues/list",
    redaction_ref: "redaction://tenant-1/github",
    usage_contexts: [:tool_task, :eval_dataset_loader, :generated_sdk, :appkit_management_api]
  )
```

Descriptors reject unmanaged auth material such as raw keys, bearer strings,
token files, default clients, request auth overrides, and provider payloads.

## Governed Example

Governed execution starts from an authority-materialized value. Direct
`base_url`, `headers`, `auth`, request header overrides, request auth
overrides, and OAuth saved-token sources are rejected when
`governed_authority` is present.

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

{:ok, response} = Pristine.execute_request(request, context)
```

## Unary Cancellation And Transport Capabilities (Pristine 0.4.0)

Cancellation support is explicit and fail-closed. A transport that only
implements the historical `c:Pristine.Ports.Transport.send/2` callback continues
to work for ordinary calls, but a call that supplies `cancellation:` requires
positive `:unary_cancellation` and `:cancellation_cleanup` advertisements plus
`send_cancelable/3`. Pristine never falls back to `send/2` for that call.

Inspect the configured contract without performing an HTTP request:

```elixir
report = Pristine.RuntimeCapabilities.transport(context)

case report.capabilities.unary_cancellation.status do
  :supported -> :transport_declares_support
  :unsupported -> :transport_declares_no_support
  :unverified -> :fail_closed
end
```

A supported transport can receive an opaque cancellation token:

```elixir
cancellation = Pristine.Cancellation.new()

task =
  Task.async(fn ->
    Pristine.execute_request(request, context, cancellation: cancellation)
  end)

:ok = Pristine.Cancellation.cancel(cancellation)

case Task.await(task) do
  {:error, %Pristine.Error{type: :cancelled}} -> :cancelled
  {:ok, response} -> {:completed, response}
end
```

Cancellation is not a transaction rollback. Once a request has been submitted,
the upstream service may already have received or begun processing it even when
the local HTTP operation is physically terminated. Pristine does not claim
exactly-once or remote side-effect rollback semantics.

**Built-in transport:** `Pristine.Adapters.Transport.Finch` supports unary
cancellation and cleanup through Execution Plane HTTP 0.2.0 sessions and OTP
`:httpc`. The compatibility name does not imply Finch/Mint owns unary requests.
Real HTTP/1.1 socket tests cover cancellation, normal completion, and caller death.
This does not claim HTTP/2 unary support. Default retry waits also wake on
cancellation; custom sleepers must cooperate to interrupt their own blocking work.

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
- governed mode accepts only explicit authority materialization and keeps direct
  env, default auth, token files, and local config in standalone compatibility
  mode

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

The Foundation retry adapter accepts `retry_budget_ms: 30_000` to stop before
a retry delay would reach the total call budget, preserving the last result.
A zero `base_ms` or `max_ms` disables backoff while retaining Retry-After delays.
