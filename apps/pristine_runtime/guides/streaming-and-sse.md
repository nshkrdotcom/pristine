# Streaming And SSE

`Pristine.stream/3` consumes the same `Pristine.Operation` envelope as
`Pristine.execute/3`. Streaming transports return a `Pristine.Response` whose
`:stream` field yields events lazily.

## Build A Streaming Client

This direct streaming client is standalone compatibility. Governed streaming
uses `governed_authority` and rejects env-backed `default_auth` and direct
headers.

```elixir
client =
  Pristine.Client.new(
    base_url: "https://api.example.com",
    stream_transport: Pristine.Adapters.Transport.FinchStream,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON,
    default_auth: [Pristine.Adapters.Auth.Bearer.new(System.fetch_env!("API_TOKEN"))]
  )
```

```elixir
authority =
  Pristine.GovernedAuthority.new!(
    base_url: "https://api.example.com",
    credential_ref: "credential:example:workspace-123",
    credential_lease_ref: "lease:example:one-effect",
    target_ref: "target:example:production",
    redaction_ref: "redaction:headers",
    credential_headers: %{"authorization" => "Bearer authority-materialized-token"}
  )

client =
  Pristine.Client.new(
    governed_authority: authority,
    stream_transport: Pristine.Adapters.Transport.FinchStream,
    transport_opts: [finch: MyApp.Finch],
    serializer: Pristine.Adapters.Serializer.JSON
  )
```

## Stream An SSE Operation

```elixir
operation =
  Pristine.Operation.new(%{
    id: "events.stream",
    method: :get,
    path_template: "/v1/events",
    headers: %{"accept" => "text/event-stream"},
    auth: %{
      use_client_default?: true,
      override: nil,
      security_schemes: ["bearerAuth"]
    },
    runtime: %{
      resource: "events",
      retry_group: "events.read",
      circuit_breaker: "events_api",
      rate_limit_group: "events.integration",
      telemetry_event: [:my_sdk, :events, :stream],
      timeout_ms: nil
    }
  })

{:ok, response} = Pristine.stream(client, operation)

response.stream
|> Enum.each(fn event ->
  IO.inspect(event, label: "event")
end)
```

For SSE helpers, combine `Pristine.stream/3` with `Pristine.Streaming.Event`,
`Pristine.Streaming.SSEDecoder`, and the stream transport adapters.
