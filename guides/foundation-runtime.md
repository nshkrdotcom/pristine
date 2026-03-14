# Foundation Runtime

`Pristine.context/1` exposes the raw ports-and-adapters surface. That is still
useful when you want complete manual control, but most production clients want
the same cohesive runtime shape: retries, learned backoff, circuit breaking,
structured telemetry, and optional admission control.

Use `Pristine.foundation_context/1` or
`Pristine.SDK.Profiles.Foundation.context/1`
for that shared production path.

## Recommended Entry Point

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [{Pristine.Adapters.Auth.Bearer, token: System.fetch_env!("API_TOKEN")}],
    retry: [max_attempts: 3],
    rate_limit: [key: {:my_app, :integration}, registry: MyApp.RateLimits],
    circuit_breaker: [registry: MyApp.Breakers],
    telemetry: [namespace: [:my_sdk], metadata: %{service: :my_sdk}]
  )
```

Everything not related to the production seams is forwarded into
`Pristine.context/1`.

## Defaults

If you do not override them, the Foundation profile enables:

- `retry: [adapter: Pristine.Adapters.Retry.Foundation, max_attempts: 2]`
- `rate_limit: [adapter: Pristine.Adapters.RateLimit.BackoffWindow]`
- `circuit_breaker: [adapter: Pristine.Adapters.CircuitBreaker.Foundation]`
- `telemetry: [adapter: Pristine.Adapters.Telemetry.Foundation, namespace: [:pristine]]`
- `admission_control: false`

You can disable any seam explicitly with `false`:

```elixir
context =
  Pristine.foundation_context(
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    retry: false,
    rate_limit: false,
    circuit_breaker: false,
    telemetry: false
  )
```

## Telemetry Export

The recommended telemetry model is:

1. emit normal `:telemetry` events through `Pristine.Adapters.Telemetry.Foundation`
2. attach handlers locally for metrics and logging
3. optionally attach `TelemetryReporter` as an exporter

That exporter path requires the optional `:telemetry_reporter` dependency.
Add it directly to the consuming application's dependencies when you use this
exporter path; `:pristine` no longer starts it as a transitive runtime app.

Supervise a reporter:

```elixir
children = [
  {Finch, name: MyApp.Finch},
  Pristine.SDK.Profiles.Foundation.reporter_child_spec(
    name: MyApp.TelemetryReporter,
    transport: MyApp.TelemetryTransport
  )
]
```

Attach it to the events defined by the context:

```elixir
{:ok, handler_id} =
  Pristine.SDK.Profiles.Foundation.attach_reporter(
    context,
    reporter: MyApp.TelemetryReporter
  )
```

You can inspect or reuse the derived event list directly:

```elixir
events = Pristine.SDK.Profiles.Foundation.reporter_events(context)
```

Detach the exporter when appropriate:

```elixir
:ok = Pristine.SDK.Profiles.Foundation.detach_reporter(handler_id)
```

## Low-Level Escape Hatch

Stay on `Pristine.context/1` when you need to:

- wire custom adapters directly
- opt into a non-Foundation retry or telemetry adapter
- construct deliberately partial contexts for tests
- experiment with extension seams outside the recommended production profile

The profile exists to remove duplicated runtime wiring from SDKs and client
applications, not to hide the underlying ports/adapters model.
