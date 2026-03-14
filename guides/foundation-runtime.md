# Foundation Runtime

`Pristine.context/1` exposes the raw ports-and-adapters surface. That is still
useful when you want complete manual control, but most production callers want
the same cohesive runtime shape: retries, learned backoff, circuit breaking,
structured telemetry, and optional admission control.

Use `Pristine.foundation_context/1` or
`Pristine.SDK.Profiles.Foundation.context/1` for that shared production path.

## Recommended Entry Point

```elixir
context =
  Pristine.foundation_context(
    base_url: "https://api.example.com",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))],
    retry: [max_attempts: 3],
    rate_limit: [key: {:my_app, :integration}, registry: MyApp.RateLimits],
    circuit_breaker: [registry: MyApp.Breakers],
    telemetry: [namespace: [:my_sdk], metadata: %{service: :my_sdk}],
    admission_control: [dispatch: MyApp.ApiDispatch]
  )
```

The Foundation profile treats these keys as feature seams:

- `retry`
- `rate_limit`
- `circuit_breaker`
- `telemetry`
- `admission_control`

Everything else passes through to `Pristine.context/1`.

## Defaults

If you do not override them, the Foundation profile enables:

- `retry: [adapter: Pristine.Adapters.Retry.Foundation, max_attempts: 2]`
- `rate_limit: [adapter: Pristine.Adapters.RateLimit.BackoffWindow]`
- `circuit_breaker: [adapter: Pristine.Adapters.CircuitBreaker.Foundation]`
- `telemetry: [adapter: Pristine.Adapters.Telemetry.Foundation, namespace: [:pristine]]`
- `admission_control: false`

The default telemetry event map comes from
`Pristine.SDK.Profiles.Foundation.default_telemetry_events/1` and includes
request and stream events such as:

- `request_start`
- `request_stop`
- `request_exception`
- `stream_start`
- `stream_connected`
- `stream_error`

You can disable any seam explicitly with `false`:

```elixir
context =
  Pristine.foundation_context(
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    retry: false,
    rate_limit: false,
    circuit_breaker: false,
    telemetry: false,
    admission_control: false
  )
```

## Admission Control

Foundation-backed admission control is disabled by default.

When you enable it, a `dispatch:` handle is required:

```elixir
context =
  Pristine.foundation_context(
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    admission_control: [dispatch: MyApp.ApiDispatch]
  )
```

If you set `admission_control: true` or omit the `dispatch:` handle, the
profile raises instead of silently degrading to a noop.

## Telemetry Export

The recommended telemetry model is:

1. emit normal `:telemetry` events through `Pristine.Adapters.Telemetry.Foundation`
2. attach handlers locally for metrics and logging
3. optionally attach `TelemetryReporter` as an exporter

That exporter path requires the optional `:telemetry_reporter` dependency.
Add it directly to the consuming application's dependencies when you use this
exporter path; `:pristine` does not start it as a transitive runtime app.

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

Attach it to the events derived from a context:

```elixir
{:ok, handler_id} =
  Pristine.SDK.Profiles.Foundation.attach_reporter(
    context,
    reporter: MyApp.TelemetryReporter
  )
```

Inspect or reuse the event list directly:

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
- opt into a non-Foundation retry, telemetry, or admission-control adapter
- construct deliberately partial contexts for tests
- pass through raw runtime options such as `headers`, `multipart`, `pool_base`, or `pool_manager`

The profile exists to remove duplicated runtime wiring from SDKs and client
applications, not to hide the underlying ports/adapters model.
