# Stage 2: Streaming Infrastructure Implementation Prompt

**Estimated Effort**: 7-10 days
**Prerequisites**: Stage 0 Complete (Stage 1 can run in parallel)
**Goal**: All tests pass, no warnings, no errors, no dialyzer errors, no `mix credo --strict` errors

---

## Context

You are implementing Stage 2 of the Pristine architecture buildout. This stage focuses on building complete streaming infrastructure including SSE (Server-Sent Events) decoding, streaming transport, and future/polling abstractions.

**Critical Note**: This is currently a complete gap - Pristine has NO streaming support. You will be building this from scratch, using the Tinkex implementation as a reference.

---

## Required Reading

### Architecture Documentation
```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/05-streaming-futures-async.md
```

### Pristine Source Files (Current State)
```
/home/home/p/g/n/pristine/lib/pristine/ports/transport.ex
/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex
/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex
/home/home/p/g/n/pristine/lib/pristine/core/response.ex
/home/home/p/g/n/pristine/lib/pristine/core/context.ex
```

### Reference: Tinkex Streaming Implementation (PORT THESE)
```
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/stream_response.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/futures.ex
```

### Reference: Tinker Python Streaming
```
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_streaming.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/futures.py
```

### Foundation Library (for backoff in polling)
```
/home/home/p/g/n/foundation/lib/foundation/backoff.ex
/home/home/p/g/n/foundation/lib/foundation/retry.ex
```

---

## Tasks

### Task 2.1: SSE Event Struct (0.5 day)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/streaming/event.ex`
- `/home/home/p/g/n/pristine/test/pristine/streaming/event_test.exs`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/streaming/event_test.exs
defmodule Pristine.Streaming.EventTest do
  use ExUnit.Case, async: true

  alias Pristine.Streaming.Event

  describe "struct" do
    test "has event, data, id, and retry fields" do
      event = %Event{
        event: "message",
        data: ~s({"foo": "bar"}),
        id: "123",
        retry: 5000
      }

      assert event.event == "message"
      assert event.data == ~s({"foo": "bar"})
      assert event.id == "123"
      assert event.retry == 5000
    end

    test "fields default to nil" do
      event = %Event{}
      assert is_nil(event.event)
      assert is_nil(event.data)
      assert is_nil(event.id)
      assert is_nil(event.retry)
    end
  end

  describe "json/1" do
    test "parses JSON data field" do
      event = %Event{data: ~s({"name": "test", "value": 42})}

      assert {:ok, parsed} = Event.json(event)
      assert parsed["name"] == "test"
      assert parsed["value"] == 42
    end

    test "returns error for invalid JSON" do
      event = %Event{data: "not json"}

      assert {:error, _} = Event.json(event)
    end

    test "returns error for nil data" do
      event = %Event{data: nil}

      assert {:error, _} = Event.json(event)
    end

    test "handles empty string data" do
      event = %Event{data: ""}

      assert {:error, _} = Event.json(event)
    end
  end

  describe "json!/1" do
    test "parses JSON and returns result directly" do
      event = %Event{data: ~s({"key": "value"})}

      assert %{"key" => "value"} = Event.json!(event)
    end

    test "raises on invalid JSON" do
      event = %Event{data: "invalid"}

      assert_raise Jason.DecodeError, fn ->
        Event.json!(event)
      end
    end
  end
end
```

2. **Implement Event Struct**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/streaming/event.ex
defmodule Pristine.Streaming.Event do
  @moduledoc """
  Represents a Server-Sent Event (SSE).

  ## Fields

    * `:event` - Event type (optional, defaults to "message" per SSE spec)
    * `:data` - Event data as string
    * `:id` - Event ID for reconnection (optional)
    * `:retry` - Retry interval in milliseconds (optional)

  ## Example

      %Event{
        event: "update",
        data: ~s({"status": "complete"}),
        id: "evt_123"
      }
  """

  @type t :: %__MODULE__{
          event: String.t() | nil,
          data: String.t() | nil,
          id: String.t() | nil,
          retry: non_neg_integer() | nil
        }

  defstruct [:event, :data, :id, :retry]

  @doc """
  Parse the event's data field as JSON.

  Returns `{:ok, term()}` on success or `{:error, reason}` on failure.
  """
  @spec json(t()) :: {:ok, term()} | {:error, term()}
  def json(%__MODULE__{data: nil}), do: {:error, :no_data}
  def json(%__MODULE__{data: ""}), do: {:error, :empty_data}

  def json(%__MODULE__{data: data}) when is_binary(data) do
    Jason.decode(data)
  end

  @doc """
  Parse the event's data field as JSON, raising on error.
  """
  @spec json!(t()) :: term()
  def json!(%__MODULE__{data: data}) when is_binary(data) do
    Jason.decode!(data)
  end
end
```

---

### Task 2.2: SSE Decoder (2 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/streaming/sse_decoder.ex`
- `/home/home/p/g/n/pristine/test/pristine/streaming/sse_decoder_test.exs`

**Reference**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

**TDD Steps**:

1. **Write Comprehensive Tests First**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/streaming/sse_decoder_test.exs
defmodule Pristine.Streaming.SSEDecoderTest do
  use ExUnit.Case, async: true

  alias Pristine.Streaming.{SSEDecoder, Event}

  describe "new/0" do
    test "creates empty decoder" do
      decoder = SSEDecoder.new()
      assert decoder.buffer == ""
    end
  end

  describe "feed/2" do
    test "parses complete single event" do
      decoder = SSEDecoder.new()
      chunk = "event: message\ndata: {\"foo\":\"bar\"}\n\n"

      {events, _new_decoder} = SSEDecoder.feed(decoder, chunk)

      assert [%Event{event: "message", data: ~s({"foo":"bar"})}] = events
    end

    test "handles chunked delivery" do
      decoder = SSEDecoder.new()

      # First chunk - incomplete
      {events1, decoder1} = SSEDecoder.feed(decoder, "data: par")
      assert events1 == []

      # Second chunk - completes the event
      {events2, _decoder2} = SSEDecoder.feed(decoder1, "tial\n\n")
      assert [%Event{data: "partial"}] = events2
    end

    test "parses multiple events in single chunk" do
      decoder = SSEDecoder.new()
      chunk = "data: first\n\ndata: second\n\n"

      {events, _decoder} = SSEDecoder.feed(decoder, chunk)

      assert [%Event{data: "first"}, %Event{data: "second"}] = events
    end

    test "handles multi-line data" do
      decoder = SSEDecoder.new()
      chunk = "data: line1\ndata: line2\ndata: line3\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "line1\nline2\nline3"
    end

    test "parses event type" do
      decoder = SSEDecoder.new()
      chunk = "event: custom_type\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "custom_type"
      assert event.data == "payload"
    end

    test "parses event id" do
      decoder = SSEDecoder.new()
      chunk = "id: evt_123\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.id == "evt_123"
    end

    test "parses retry interval" do
      decoder = SSEDecoder.new()
      chunk = "retry: 5000\ndata: payload\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.retry == 5000
    end

    test "ignores comment lines" do
      decoder = SSEDecoder.new()
      chunk = ": this is a comment\ndata: actual_data\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "actual_data"
    end

    test "handles \\r\\n line endings" do
      decoder = SSEDecoder.new()
      chunk = "data: test\r\n\r\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "test"
    end

    test "handles \\r line endings" do
      decoder = SSEDecoder.new()
      chunk = "data: test\r\r"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "test"
    end

    test "handles mixed line endings" do
      decoder = SSEDecoder.new()
      chunk = "event: test\r\ndata: mixed\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "test"
      assert event.data == "mixed"
    end

    test "preserves last_event_id across events" do
      decoder = SSEDecoder.new()

      # First event sets ID
      {[event1], decoder1} = SSEDecoder.feed(decoder, "id: 1\ndata: first\n\n")
      assert event1.id == "1"

      # Second event without ID should NOT inherit (per SSE spec, id is per-event)
      {[event2], _decoder2} = SSEDecoder.feed(decoder1, "data: second\n\n")
      assert event2.id == nil
    end

    test "ignores invalid retry values" do
      decoder = SSEDecoder.new()
      chunk = "retry: not_a_number\ndata: test\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.retry == nil
      assert event.data == "test"
    end

    test "handles empty data field" do
      decoder = SSEDecoder.new()
      chunk = "event: ping\ndata:\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.event == "ping"
      assert event.data == ""
    end

    test "handles field without colon space" do
      decoder = SSEDecoder.new()
      chunk = "data:no_space\n\n"

      {[event], _decoder} = SSEDecoder.feed(decoder, chunk)

      assert event.data == "no_space"
    end

    test "returns remaining buffer for incomplete events" do
      decoder = SSEDecoder.new()
      chunk = "data: incomplete"

      {events, new_decoder} = SSEDecoder.feed(decoder, chunk)

      assert events == []
      assert new_decoder.buffer =~ "incomplete"
    end
  end

  describe "decode_stream/1" do
    test "creates stream from enumerable of chunks" do
      chunks = ["data: one\n\n", "data: two\n\n"]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert [%Event{data: "one"}, %Event{data: "two"}] = events
    end

    test "handles chunked data across stream" do
      chunks = ["data: spl", "it_data\n\n"]

      events =
        chunks
        |> SSEDecoder.decode_stream()
        |> Enum.to_list()

      assert [%Event{data: "split_data"}] = events
    end
  end
end
```

2. **Implement SSE Decoder**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/streaming/sse_decoder.ex
defmodule Pristine.Streaming.SSEDecoder do
  @moduledoc """
  Stateful decoder for Server-Sent Events (SSE) streams.

  Implements the SSE specification: https://html.spec.whatwg.org/multipage/server-sent-events.html

  ## Usage

      decoder = SSEDecoder.new()
      {events, decoder} = SSEDecoder.feed(decoder, chunk)

  ## Streaming Usage

      chunks
      |> SSEDecoder.decode_stream()
      |> Enum.each(&process_event/1)
  """

  alias Pristine.Streaming.Event

  @type t :: %__MODULE__{
          buffer: binary()
        }

  defstruct buffer: ""

  @event_terminators ["\n\n", "\r\n\r\n", "\r\r"]

  @doc "Create a new decoder."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Feed a chunk of data to the decoder.

  Returns `{events, new_decoder}` where `events` is a list of complete
  events parsed from the accumulated data.
  """
  @spec feed(t(), binary()) :: {[Event.t()], t()}
  def feed(%__MODULE__{buffer: buffer} = _decoder, chunk) when is_binary(chunk) do
    data = buffer <> chunk
    {events, rest} = parse_events(data, [])
    {Enum.reverse(events), %__MODULE__{buffer: rest}}
  end

  @doc """
  Create a stream of events from an enumerable of chunks.
  """
  @spec decode_stream(Enumerable.t()) :: Enumerable.t()
  def decode_stream(chunks) do
    Stream.transform(chunks, new(), fn chunk, decoder ->
      {events, new_decoder} = feed(decoder, chunk)
      {events, new_decoder}
    end)
  end

  # Parse complete events from the buffer
  defp parse_events(data, acc) do
    case find_event_boundary(data) do
      nil ->
        {acc, data}

      {event_data, rest} ->
        event = parse_event(event_data)
        parse_events(rest, [event | acc])
    end
  end

  defp find_event_boundary(data) do
    Enum.find_value(@event_terminators, fn terminator ->
      case :binary.split(data, terminator) do
        [event_data, rest] -> {event_data, rest}
        [_] -> nil
      end
    end)
  end

  defp parse_event(event_data) do
    event_data
    |> String.split(~r/\r\n|\n|\r/)
    |> Enum.reduce(%Event{}, &parse_line/2)
    |> finalize_event()
  end

  defp parse_line(":" <> _comment, event), do: event  # Ignore comments

  defp parse_line(line, event) do
    case String.split(line, ":", parts: 2) do
      [field, value] ->
        # Remove leading space from value if present
        value = String.replace_prefix(value, " ", "")
        apply_field(event, field, value)

      [field] ->
        apply_field(event, field, "")
    end
  end

  defp apply_field(event, "event", value), do: %{event | event: value}
  defp apply_field(event, "id", value), do: %{event | id: value}

  defp apply_field(event, "retry", value) do
    case Integer.parse(value) do
      {int, ""} -> %{event | retry: int}
      _ -> event
    end
  end

  defp apply_field(event, "data", value) do
    case event.data do
      nil -> %{event | data: value}
      existing -> %{event | data: existing <> "\n" <> value}
    end
  end

  defp apply_field(event, _unknown_field, _value), do: event

  defp finalize_event(%Event{data: nil} = event), do: %{event | data: ""}
  defp finalize_event(event), do: event
end
```

---

### Task 2.3: Stream Transport Port and Response (1-2 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/stream_transport.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/stream_response.ex`
- `/home/home/p/g/n/pristine/test/pristine/core/stream_response_test.exs`

**TDD Steps**:

1. **Create Stream Response Struct**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/core/stream_response.ex
defmodule Pristine.Core.StreamResponse do
  @moduledoc """
  Response wrapper for streaming HTTP responses.

  Contains an enumerable stream of events instead of a complete body.
  """

  @type t :: %__MODULE__{
          stream: Enumerable.t(),
          status: integer(),
          headers: map(),
          metadata: map()
        }

  @enforce_keys [:stream, :status, :headers]
  defstruct [:stream, :status, :headers, metadata: %{}]
end
```

2. **Create Stream Transport Port**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/ports/stream_transport.ex
defmodule Pristine.Ports.StreamTransport do
  @moduledoc """
  Port for streaming HTTP transport.

  Unlike the regular Transport port which returns complete responses,
  this port returns StreamResponse with an enumerable body.
  """

  alias Pristine.Core.{Request, Context, StreamResponse}

  @callback stream(Request.t(), Context.t()) ::
              {:ok, StreamResponse.t()} | {:error, term()}
end
```

---

### Task 2.4: Finch Streaming Adapter (2 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch_stream.ex`
- `/home/home/p/g/n/pristine/test/pristine/adapters/transport/finch_stream_test.exs`

**TDD Steps**:

1. **Write Tests** (using Bypass for HTTP mocking):

```elixir
# /home/home/p/g/n/pristine/test/pristine/adapters/transport/finch_stream_test.exs
defmodule Pristine.Adapters.Transport.FinchStreamTest do
  use ExUnit.Case, async: false

  alias Pristine.Adapters.Transport.FinchStream
  alias Pristine.Core.{Request, Context, StreamResponse}
  alias Pristine.Streaming.Event

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "stream/2" do
    test "streams SSE events", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_event("data: {\"n\":1}\n\n")
        |> send_sse_event("data: {\"n\":2}\n\n")
      end)

      request = %Request{
        method: :get,
        url: "http://localhost:#{bypass.port}/stream",
        headers: %{},
        body: nil
      }

      context = %Context{
        transport_opts: [finch: Pristine.Finch]
      }

      assert {:ok, %StreamResponse{} = response} = FinchStream.stream(request, context)
      assert response.status == 200

      events = Enum.to_list(response.stream)
      assert length(events) == 2
      assert [%Event{data: ~s({"n":1})}, %Event{data: ~s({"n":2})}] = events
    end

    test "handles connection errors", %{bypass: bypass} do
      Bypass.down(bypass)

      request = %Request{
        method: :get,
        url: "http://localhost:#{bypass.port}/stream",
        headers: %{},
        body: nil
      }

      context = %Context{transport_opts: [finch: Pristine.Finch]}

      assert {:error, _reason} = FinchStream.stream(request, context)
    end
  end

  defp send_sse_event(conn, event_data) do
    {:ok, conn} = Plug.Conn.chunk(conn, event_data)
    conn
  end
end
```

2. **Implement Finch Streaming Adapter**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch_stream.ex
defmodule Pristine.Adapters.Transport.FinchStream do
  @moduledoc """
  Streaming HTTP transport adapter using Finch.

  Uses Finch.stream/5 to handle chunked responses and SSE streams.
  """

  @behaviour Pristine.Ports.StreamTransport

  alias Pristine.Core.{Request, Context, StreamResponse}
  alias Pristine.Streaming.SSEDecoder

  @impl true
  def stream(%Request{} = request, %Context{} = context) do
    finch_name = get_finch_name(context)
    timeout = Keyword.get(context.transport_opts, :receive_timeout, 60_000)

    finch_request = build_finch_request(request)

    # Create a stream that accumulates chunks and decodes SSE events
    stream = create_event_stream(finch_request, finch_name, timeout)

    # We need to get headers/status before returning
    # This is tricky with streaming - we'll use a reference to capture them
    case get_response_metadata(finch_request, finch_name, timeout) do
      {:ok, status, headers} ->
        {:ok, %StreamResponse{
          stream: stream,
          status: status,
          headers: headers,
          metadata: %{}
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_finch_name(%Context{transport_opts: opts}) do
    Keyword.get(opts, :finch, Pristine.Finch)
  end

  defp build_finch_request(%Request{method: method, url: url, headers: headers, body: body}) do
    header_list = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    Finch.build(method, url, header_list, body)
  end

  defp get_response_metadata(request, finch_name, timeout) do
    # Make a HEAD-like request or use streaming to get just metadata
    case Finch.request(request, finch_name, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, headers: headers}} ->
        {:ok, status, Map.new(headers)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_event_stream(request, finch_name, timeout) do
    Stream.resource(
      fn -> init_stream(request, finch_name, timeout) end,
      &next_events/1,
      &cleanup_stream/1
    )
  end

  defp init_stream(request, finch_name, timeout) do
    # Start streaming request
    ref = make_ref()
    parent = self()

    task = Task.async(fn ->
      Finch.stream(request, finch_name, {SSEDecoder.new(), []},
        fn
          {:status, status}, {decoder, events} ->
            send(parent, {ref, :status, status})
            {decoder, events}

          {:headers, headers}, {decoder, events} ->
            send(parent, {ref, :headers, headers})
            {decoder, events}

          {:data, chunk}, {decoder, events} ->
            {new_events, new_decoder} = SSEDecoder.feed(decoder, chunk)
            {new_decoder, events ++ new_events}
        end,
        receive_timeout: timeout
      )
    end)

    %{task: task, ref: ref, buffer: []}
  end

  defp next_events(%{buffer: [event | rest]} = state) do
    {[event], %{state | buffer: rest}}
  end

  defp next_events(%{task: task} = state) do
    case Task.yield(task, 100) do
      nil ->
        # Still running, no events yet
        {[], state}

      {:ok, {:ok, {_decoder, events}}} ->
        # Completed
        {events, :done}

      {:ok, {:error, _reason}} ->
        {:halt, state}

      {:exit, _reason} ->
        {:halt, state}
    end
  end

  defp cleanup_stream(:done), do: :ok
  defp cleanup_stream(%{task: task}), do: Task.shutdown(task, :brutal_kill)
end
```

---

### Task 2.5: Future/Polling Port and Adapter (3 days)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/future.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/future/polling.ex`
- `/home/home/p/g/n/pristine/test/pristine/adapters/future/polling_test.exs`

**Reference**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`

**TDD Steps**:

1. **Write Tests**:

```elixir
# /home/home/p/g/n/pristine/test/pristine/adapters/future/polling_test.exs
defmodule Pristine.Adapters.Future.PollingTest do
  use ExUnit.Case, async: false

  alias Pristine.Adapters.Future.Polling
  alias Pristine.Core.Context

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "poll/3" do
    test "returns task that polls until complete", %{bypass: bypass} do
      poll_count = :counters.new(1, [:atomics])

      Bypass.expect(bypass, fn conn ->
        count = :counters.get(poll_count, 1)
        :counters.add(poll_count, 1, 1)

        response = if count < 2 do
          %{"status" => "pending", "type" => "try_again"}
        else
          %{"status" => "complete", "result" => %{"value" => 42}}
        end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      context = build_context(bypass.port)
      opts = [poll_interval_ms: 10, max_poll_time_ms: 5000]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:ok, result} = Task.await(task, 10_000)
      assert result["status"] == "complete"
      assert result["result"]["value"] == 42
    end

    test "times out after max_poll_time_ms", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        response = %{"status" => "pending", "type" => "try_again"}
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      context = build_context(bypass.port)
      opts = [poll_interval_ms: 10, max_poll_time_ms: 50]

      {:ok, task} = Polling.poll("req_123", context, opts)

      assert {:error, :poll_timeout} = Task.await(task, 5_000)
    end

    test "uses exponential backoff", %{bypass: bypass} do
      timestamps = :ets.new(:timestamps, [:set, :public])

      Bypass.expect(bypass, fn conn ->
        :ets.insert(timestamps, {System.monotonic_time(:millisecond), true})
        response = %{"status" => "pending", "type" => "try_again"}
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      context = build_context(bypass.port)
      opts = [
        poll_interval_ms: 10,
        max_poll_time_ms: 200,
        backoff: :exponential
      ]

      {:ok, task} = Polling.poll("req_123", context, opts)
      Task.await(task, 5_000)

      # Verify intervals increased
      times = :ets.tab2list(timestamps) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      intervals = Enum.zip(times, tl(times)) |> Enum.map(fn {a, b} -> b - a end)

      # Later intervals should be larger
      assert Enum.at(intervals, -1) >= Enum.at(intervals, 0)
    end
  end

  describe "await/2" do
    test "returns result when task completes", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        response = %{"status" => "complete", "result" => "done"}
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      context = build_context(bypass.port)
      {:ok, task} = Polling.poll("req_123", context, [])

      assert {:ok, %{"status" => "complete"}} = Polling.await(task, 5_000)
    end
  end

  defp build_context(port) do
    %Context{
      base_url: "http://localhost:#{port}",
      headers: %{},
      transport: Pristine.Adapters.Transport.Finch,
      transport_opts: [finch: Pristine.Finch],
      serializer: Pristine.Adapters.Serializer.JSON
    }
  end
end
```

2. **Create Future Port**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/ports/future.ex
defmodule Pristine.Ports.Future do
  @moduledoc """
  Port for future/async result polling.
  """

  alias Pristine.Core.Context

  @type poll_opts :: [
          poll_interval_ms: non_neg_integer(),
          max_poll_time_ms: non_neg_integer() | :infinity,
          backoff: :none | :linear | :exponential,
          on_state_change: (map() -> :ok) | nil
        ]

  @callback poll(request_id :: String.t(), Context.t(), poll_opts()) ::
              {:ok, Task.t()} | {:error, term()}

  @callback await(Task.t(), timeout()) ::
              {:ok, term()} | {:error, term()}
end
```

3. **Implement Polling Adapter**:

```elixir
# /home/home/p/g/n/pristine/lib/pristine/adapters/future/polling.ex
defmodule Pristine.Adapters.Future.Polling do
  @moduledoc """
  Future polling adapter with configurable backoff.
  """

  @behaviour Pristine.Ports.Future

  alias Pristine.Core.{Context, Pipeline}
  alias Foundation.Backoff

  @default_poll_interval_ms 1_000
  @default_max_poll_time_ms 300_000  # 5 minutes

  defmodule State do
    @moduledoc false
    defstruct [
      :request_id,
      :context,
      :retrieve_endpoint,
      :backoff_policy,
      :max_poll_time_ms,
      :on_state_change,
      :start_time
    ]
  end

  @impl true
  def poll(request_id, %Context{} = context, opts \\ []) do
    state = build_state(request_id, context, opts)
    task = Task.async(fn -> poll_loop(state, 0) end)
    {:ok, task}
  end

  @impl true
  def await(task, timeout) do
    Task.await(task, timeout)
  end

  defp build_state(request_id, context, opts) do
    interval = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    max_time = Keyword.get(opts, :max_poll_time_ms, @default_max_poll_time_ms)
    backoff_type = Keyword.get(opts, :backoff, :exponential)

    backoff_policy = Backoff.Policy.new(
      strategy: backoff_type,
      base_ms: interval,
      max_ms: interval * 10
    )

    %State{
      request_id: request_id,
      context: context,
      retrieve_endpoint: Keyword.get(opts, :retrieve_endpoint, :retrieve_future),
      backoff_policy: backoff_policy,
      max_poll_time_ms: max_time,
      on_state_change: Keyword.get(opts, :on_state_change),
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp poll_loop(%State{} = state, attempt) do
    if timed_out?(state) do
      {:error, :poll_timeout}
    else
      case do_retrieve(state) do
        {:ok, %{"type" => "try_again"} = response} ->
          notify_state_change(state, response)
          delay = calculate_delay(state.backoff_policy, attempt)
          Process.sleep(delay)
          poll_loop(state, attempt + 1)

        {:ok, response} ->
          {:ok, response}

        {:error, reason} when is_retriable?(reason) ->
          delay = calculate_delay(state.backoff_policy, attempt)
          Process.sleep(delay)
          poll_loop(state, attempt + 1)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp timed_out?(%State{max_poll_time_ms: :infinity}), do: false

  defp timed_out?(%State{start_time: start, max_poll_time_ms: max}) do
    System.monotonic_time(:millisecond) - start > max
  end

  defp do_retrieve(%State{request_id: id, context: context, retrieve_endpoint: endpoint}) do
    payload = %{"request_id" => id}
    # This would call the actual retrieve endpoint
    # For now, use a direct HTTP call
    Pipeline.execute_direct(context, :post, "/api/v1/retrieve_future", payload)
  end

  defp calculate_delay(policy, attempt) do
    Backoff.calculate(policy, attempt)
  end

  defp notify_state_change(%State{on_state_change: nil}, _response), do: :ok
  defp notify_state_change(%State{on_state_change: fun}, response), do: fun.(response)

  defp is_retriable?({:http_error, status}) when status in [408, 429, 500, 502, 503, 504], do: true
  defp is_retriable?(:timeout), do: true
  defp is_retriable?(_), do: false
end
```

---

### Task 2.6: Pipeline Streaming Integration (1 day)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/context.ex`

**TDD Steps**:

Add `execute_stream/5` function to Pipeline.

---

## Verification Checklist

```bash
cd /home/home/p/g/n/pristine

# All tests pass
mix test

# No warnings
mix compile --warnings-as-errors

# Credo passes
mix credo --strict

# Dialyzer passes
mix dialyzer
```

---

## Expected Outcomes

After Stage 2 completion:

1. **SSE Decoder** parses Server-Sent Events correctly
2. **Stream Transport** returns enumerable event streams
3. **Future Polling** with configurable backoff works
4. **Pipeline** has `execute_stream/5` for streaming endpoints
5. All Tinker streaming patterns are supported
