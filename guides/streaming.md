# Streaming and SSE

Pristine provides first-class support for Server-Sent Events (SSE) and streaming HTTP responses. This guide covers the streaming architecture and usage patterns.

## Overview

Streaming in Pristine handles:

- **SSE (Server-Sent Events)** - Standard event stream protocol
- **Chunked responses** - Incremental data delivery
- **Long-running connections** - With proper cleanup and cancellation

## Architecture

```
Pipeline.execute_stream()
    │
    ├─► StreamTransport.stream()
    │   └─► Returns StreamResponse
    │
    └─► StreamResponse
        ├─► .stream (Enumerable of events)
        ├─► .status (HTTP status)
        ├─► .headers (Response headers)
        └─► .metadata
            ├─► cancel function
            └─► last_event_id
```

## Configuration

Enable streaming in your context:

```elixir
context = Pristine.context(
  base_url: "https://api.example.com",
  stream_transport: Pristine.Adapters.Transport.FinchStream,
  transport_opts: [
    finch: MyApp.Finch,
    receive_timeout: 60_000  # 60 seconds
  ],
  serializer: Pristine.Adapters.Serializer.JSON,
  auth: [{Pristine.Adapters.Auth.Bearer, token: "..."}]
)
```

## Basic Usage

### Execute Streaming Endpoint

```elixir
{:ok, manifest} = Pristine.load_manifest_file("manifest.json")

{:ok, response} = Pristine.Core.Pipeline.execute_stream(
  manifest,
  :stream_endpoint,
  %{"prompt" => "Hello"},
  context
)

# Check status
IO.puts("Status: #{response.status}")

# Consume events
response.stream
|> Enum.each(fn event ->
  IO.inspect(event)
end)
```

### StreamResponse Structure

```elixir
%Pristine.Core.StreamResponse{
  stream: #Stream<...>,           # Enumerable of events
  status: 200,                    # HTTP status code
  headers: %{                     # Response headers
    "content-type" => "text/event-stream"
  },
  metadata: %{                    # Transport metadata
    cancel: #Function<...>,       # Cancel function
    last_event_id_ref: #PID<...>  # Agent for last ID
  }
}
```

## SSE Events

### Event Structure

Each SSE event is parsed into:

```elixir
%Pristine.Streaming.Event{
  event: "message",           # Event type (default: "message")
  data: "{\"text\":\"Hi\"}",  # Event payload
  id: "evt_123",              # Event ID (optional)
  retry: 5000                 # Retry interval ms (optional)
}
```

### Parsing Event Data

```elixir
# Safe parsing (returns tuple)
case Pristine.Streaming.Event.json(event) do
  {:ok, data} ->
    IO.inspect(data)
  {:error, reason} ->
    IO.puts("Parse error: #{inspect(reason)}")
end

# Raising version
data = Pristine.Streaming.Event.json!(event)
```

### Check Event Type

```elixir
if Pristine.Streaming.Event.message?(event) do
  # Default "message" event
end
```

## Stream Processing

### Basic Iteration

```elixir
response.stream
|> Enum.each(fn event ->
  case Pristine.Streaming.Event.json(event) do
    {:ok, data} -> process_data(data)
    {:error, _} -> :skip
  end
end)
```

### With Stream Operations

```elixir
response.stream
|> Stream.map(&Pristine.Streaming.Event.json!/1)
|> Stream.filter(&keep_event?/1)
|> Stream.take(100)  # Limit events
|> Enum.to_list()
```

### Accumulating Results

```elixir
result = response.stream
|> Enum.reduce("", fn event, acc ->
  case Pristine.Streaming.Event.json(event) do
    {:ok, %{"delta" => delta}} -> acc <> delta
    _ -> acc
  end
end)
```

## Event Handlers

### Define a Handler Module

```elixir
defmodule MyEventHandler do
  def on_message_start(data) do
    IO.puts("Stream started: #{inspect(data)}")
  end

  def on_content_block_delta(data) do
    # Accumulate deltas
    IO.write(data["delta"]["text"])
  end

  def on_content_block_stop(data) do
    IO.puts("\nBlock complete")
  end

  def on_message_stop(data) do
    IO.puts("Stream complete: #{inspect(data)}")
  end

  def on_error(data) do
    IO.puts("Error: #{inspect(data)}")
  end

  def on_unknown(event_type, data) do
    IO.puts("Unknown event #{event_type}: #{inspect(data)}")
  end
end
```

### Use with StreamResponse

```elixir
# Dispatch single event
Pristine.Core.StreamResponse.dispatch_event(event, MyEventHandler)

# Dispatch entire stream
response.stream
|> Pristine.Core.StreamResponse.dispatch_stream(MyEventHandler)
|> Stream.run()
```

## Cancellation

### Cancel a Stream

```elixir
{:ok, response} = Pipeline.execute_stream(manifest, :endpoint, payload, context)

# Start consuming
task = Task.async(fn ->
  Enum.each(response.stream, &process/1)
end)

# Cancel after timeout
Process.sleep(5000)
:ok = Pristine.Core.StreamResponse.cancel(response)

# Task will complete
Task.await(task)
```

### Automatic Cleanup

Streams automatically clean up when:
- Enumeration completes
- An error occurs
- The process terminates

## Reconnection

### Last Event ID

SSE supports reconnection using the last event ID:

```elixir
# Get last ID from completed/interrupted stream
last_id = Pristine.Core.StreamResponse.last_event_id(response)

# Reconnect with last ID
new_context = put_in(context.transport_opts[:last_event_id], last_id)

{:ok, new_response} = Pipeline.execute_stream(
  manifest,
  :endpoint,
  payload,
  new_context
)
```

## SSE Decoder

### Direct Decoder Usage

For non-Pristine SSE parsing:

```elixir
alias Pristine.Streaming.SSEDecoder

# Create decoder
decoder = SSEDecoder.new()

# Feed chunks
{events, decoder} = SSEDecoder.feed(decoder, chunk1)
{more_events, decoder} = SSEDecoder.feed(decoder, chunk2)

# Or decode a stream
chunks
|> SSEDecoder.decode_stream()
|> Enum.each(&process_event/1)
```

### Decode Complete Body

```elixir
# For complete SSE body (not streaming)
events = Pristine.Adapters.Transport.FinchStream.decode_sse_body(body)
```

## SSE Format Reference

### Standard SSE Format

```
event: eventType
id: 123
retry: 5000
data: {"key": "value"}
data: more data

```

### Rules

- **Event boundaries**: Blank lines (`\n\n`)
- **Multi-line data**: Multiple `data:` lines joined with `\n`
- **Comments**: Lines starting with `:` are ignored
- **Default event type**: `"message"` when not specified

### Example SSE Stream

```
: This is a comment

event: start
data: {"status": "starting"}

data: {"delta": "Hello"}

data: {"delta": " world"}

event: done
data: {"status": "complete"}

```

## Manifest Configuration

### Streaming Endpoint

```json
{
  "endpoints": [
    {
      "id": "stream_chat",
      "method": "POST",
      "path": "/chat/completions",
      "resource": "chat",
      "streaming": true,
      "stream_format": "sse",
      "request": "ChatRequest",
      "event_types": ["message_start", "content_delta", "message_stop"]
    }
  ]
}
```

### Generated Code

With `streaming: true`, an additional function is generated:

```elixir
# Standard (non-streaming)
def completions(resource, messages, opts \\ [])

# Streaming version
def completions_stream(resource, messages, opts \\ [])
```

## Error Handling

### Connection Errors

```elixir
case Pipeline.execute_stream(manifest, :endpoint, payload, context) do
  {:ok, response} ->
    process_stream(response)

  {:error, %Mint.TransportError{reason: :timeout}} ->
    IO.puts("Connection timed out")

  {:error, reason} ->
    IO.puts("Stream error: #{inspect(reason)}")
end
```

### Stream Errors

```elixir
try do
  Enum.each(response.stream, &process/1)
rescue
  e in RuntimeError ->
    IO.puts("Stream interrupted: #{Exception.message(e)}")
end
```

## Telemetry Events

Streaming emits these telemetry events:

| Event | When |
|-------|------|
| `[:pristine, :stream, :start]` | Request initiated |
| `[:pristine, :stream, :connected]` | Headers received |
| `[:pristine, :stream, :error]` | Connection/setup error |

```elixir
:telemetry.attach(
  "stream-monitor",
  [:pristine, :stream, :connected],
  fn _event, _measurements, metadata, _config ->
    IO.puts("Connected to #{metadata.endpoint_id}")
  end,
  nil
)
```

## Performance Considerations

### Memory Efficiency

Streams are lazy - events are parsed and yielded on demand:

```elixir
# Good - processes one event at a time
response.stream
|> Stream.each(&process/1)
|> Stream.run()

# Avoid - loads all events into memory
events = Enum.to_list(response.stream)
```

### Backpressure

Consumer speed controls network reads. Slow consumers naturally apply backpressure.

### Timeouts

Configure appropriate timeouts:

```elixir
transport_opts: [
  receive_timeout: 300_000  # 5 minutes for long streams
]
```

## Complete Example

```elixir
defmodule ChatStreamer do
  alias Pristine.Core.{Pipeline, StreamResponse}
  alias Pristine.Streaming.Event

  def stream_chat(prompt) do
    {:ok, manifest} = Pristine.load_manifest_file("manifest.json")

    context = Pristine.context(
      base_url: "https://api.example.com",
      stream_transport: Pristine.Adapters.Transport.FinchStream,
      transport_opts: [finch: MyApp.Finch, receive_timeout: 60_000],
      serializer: Pristine.Adapters.Serializer.JSON,
      auth: [{Pristine.Adapters.Auth.Bearer, token: api_key()}]
    )

    case Pipeline.execute_stream(manifest, :stream_chat, %{prompt: prompt}, context) do
      {:ok, response} ->
        stream_response(response)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp stream_response(response) do
    response.stream
    |> Stream.map(&Event.json/1)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, data} -> data end)
    |> Enum.each(fn
      %{"type" => "content_delta", "delta" => %{"text" => text}} ->
        IO.write(text)

      %{"type" => "message_stop"} ->
        IO.puts("\n[Stream complete]")

      _ ->
        :ok
    end)
  end

  defp api_key, do: System.get_env("API_KEY")
end
```
