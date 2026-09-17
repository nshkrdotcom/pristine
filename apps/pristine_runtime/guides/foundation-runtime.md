# Foundation Runtime

`Pristine.Client.foundation/1` builds the recommended production client profile.
It wires the Foundation retry, rate-limit, circuit-breaker, telemetry, and
admission-control adapters into one provider-agnostic runtime client.

## Build A Foundation Client

This direct `default_auth` example is standalone compatibility. Governed
execution must use `governed_authority` instead of env-backed `default_auth`,
direct headers, or direct base URL inputs.

```elixir
client =
  Pristine.Client.foundation(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    default_auth: [Pristine.Adapters.Auth.Bearer.new("example-api-token")],
    telemetry: [namespace: [:my_sdk]]
  )
```

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

client =
  Pristine.Client.foundation(
    governed_authority: authority,
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    telemetry: [namespace: [:my_sdk]]
  )
```

## Feature Flags

`Pristine.Client.foundation/1` forwards the same top-level Foundation feature
switches used by `Pristine.Profiles.Foundation`:

- `retry`
- `rate_limit`
- `circuit_breaker`
- `telemetry`
- `admission_control`

Each feature accepts `false`, `true`, an adapter module, or an option list.

## Reporter Helpers

`Pristine.Profiles.Foundation` still exposes the telemetry reporter helpers used
by production runtimes:

```elixir
events = Pristine.Profiles.Foundation.default_telemetry_events([:my_sdk])

child_spec =
  Pristine.Profiles.Foundation.reporter_child_spec(
    handler_id: "my-sdk-reporter",
    events: Map.values(events)
  )
```

When you already have a Foundation client, pass its internal context to the
reporter helpers:

```elixir
handler_id =
  Pristine.Profiles.Foundation.attach_reporter(
    client.context,
    handler_id: "my-sdk-reporter"
  )

events = Pristine.Profiles.Foundation.reporter_events(client.context)

:ok = Pristine.Profiles.Foundation.detach_reporter(handler_id)
```

## Registry lifetime (Pristine 0.3.1 / Foundation 0.2.2)

Default breaker, rate-limit and semaphore ETS registries belong to Foundation's
supervised registry owner. Short-lived HTTP workers no longer create competing
default tables or transfer them to Erlang `:init` on exit. Foundation recovers
stale default caches after owner restart; that restart resets resilience state.

Explicit registries are caller-owned and need no heir. Create shared explicit
registries in a long-lived supervised process and pass them via adapter options.
A deleted anonymous registry is an error, not a reason to silently bypass its
limits with a replacement table. Named registry creation follows Foundation's
normal named-registry behavior. This ownership fix does not add transport queue
bounds or physical HTTP cancellation guarantees.
