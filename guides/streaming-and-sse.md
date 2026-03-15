# Streaming and SSE

Related guides: `manual-contexts-and-adapters.md`,
`testing-and-verification.md`.

Pristine keeps SSE support in a few reusable layers instead of hiding it inside
the normal request/response path:

- `Pristine.Streaming.SSEDecoder` for incremental parsing
- `Pristine.Streaming.Event` for event helpers
- `Pristine.Adapters.Streaming.SSE` for adapter-shaped decoding
- `Pristine.Adapters.Transport.FinchStream` for direct Finch-backed streaming
- `Pristine.Core.StreamResponse` for dispatch, cancellation, and last-event-id

## Decode a Complete SSE Body

```elixir
events =
  "event: message\ndata: {\"ok\":true}\n\ndata: second\n\n"
  |> Pristine.Adapters.Streaming.SSE.decode()
  |> Enum.to_list()
```

Each entry is a `Pristine.Streaming.Event` with `event`, `data`, `id`, and
`retry` fields.

## Decode Incremental Chunks

For chunk-by-chunk input, use the stateful decoder directly:

```elixir
chunks = ["data: hel", "lo\n\n", "data: world\n\n"]

events =
  chunks
  |> Pristine.Streaming.SSEDecoder.decode_stream()
  |> Enum.to_list()
```

The decoder handles:

- chunked delivery
- multi-line `data:` fields
- comment lines
- `id` and `retry` fields
- mixed `\n`, `\r\n`, and `\r` line endings

## Parse Event Data as JSON

```elixir
event = %Pristine.Streaming.Event{data: ~s({"status":"ok"})}

{:ok, payload} = Pristine.Streaming.Event.json(event)
```

Or raise on malformed data:

```elixir
payload = Pristine.Streaming.Event.json!(event)
```

## Use the Finch Streaming Transport Directly

The direct streaming transport entry point today is
`Pristine.Adapters.Transport.FinchStream` via its `stream/2` callback.

```elixir
request = %Pristine.Core.Request{
  method: :get,
  url: "https://api.example.com/events",
  headers: %{"accept" => "text/event-stream"},
  metadata: %{timeout: 30_000}
}

context =
  Pristine.context(
    transport_opts: [finch: MyApp.Finch],
    stream_transport: Pristine.Adapters.Transport.FinchStream,
    streaming: Pristine.Adapters.Streaming.SSE
  )

{:ok, response} =
  Pristine.Adapters.Transport.FinchStream.stream(request, context)

events = Enum.to_list(response.stream)
```

`response` is a `Pristine.Core.StreamResponse`.

## Work with StreamResponse Helpers

`Pristine.Core.StreamResponse` exposes a few small convenience helpers:

```elixir
Pristine.Core.StreamResponse.last_event_id(response)
Pristine.Core.StreamResponse.cancel(response)
```

It can also dispatch events through a handler module:

```elixir
defmodule MyHandler do
  def on_message_start(payload), do: {:message_start, payload}
  def on_content_block_start(payload), do: {:content_block_start, payload}
  def on_content_block_delta(payload), do: {:content_block_delta, payload}
  def on_content_block_stop(payload), do: {:content_block_stop, payload}
  def on_message_stop(payload), do: {:message_stop, payload}
  def on_error(payload), do: {:error, payload}
  def on_unknown(event, data), do: {:unknown, event, data}
end

results =
  response
  |> Pristine.Core.StreamResponse.dispatch_stream(MyHandler)
  |> Enum.to_list()
```

## Current Boundary

`Pristine.execute_request/3` remains request/response oriented. The public
streaming surface today is intentionally direct:

- use `Pristine.Adapters.Transport.FinchStream` when you need a live streaming
  HTTP connection
- use `Pristine.Streaming.SSEDecoder` and `Pristine.Adapters.Streaming.SSE`
  when you only need SSE parsing utilities

That keeps the retained runtime boundary small while still exposing the stream
building blocks that provider SDKs need.
