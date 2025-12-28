# Streaming, Futures, and Async Patterns Architecture Audit

**Date**: 2025-12-28
**Scope**: Tinker Python SDK streaming/futures/async patterns vs Pristine capabilities
**Status**: Gap Analysis Complete

---

## 1. Summary

The Tinker Python SDK provides a sophisticated streaming and async infrastructure built on httpx, featuring:

1. **SSE (Server-Sent Events) Streaming**: Full SSE decoder with sync/async iterators for real-time data consumption
2. **Stream/AsyncStream Classes**: Generic typed wrappers around httpx responses enabling lazy iteration
3. **Future/Promise Pattern**: Async resource for retrieving deferred computation results via polling
4. **Async-First Client**: `AsyncTinker` client with streaming response variants for all resources

Pristine currently has **minimal streaming support** - the transport port expects synchronous request/response patterns with no SSE handling, streaming iteration, or future/polling abstractions.

---

## 2. Detailed Analysis

### 2.1 Tinker Python SDK: Streaming Response Handling

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_streaming.py`

The Python SDK provides two core streaming classes:

#### Stream[T] (Synchronous)

```python
class Stream(Generic[_T]):
    """Provides the core interface to iterate over a synchronous stream response."""

    response: httpx.Response
    _decoder: SSEBytesDecoder

    def __init__(self, *, cast_to: type[_T], response: httpx.Response, client: Tinker):
        self._decoder = client._make_sse_decoder()
        self._iterator = self.__stream__()

    def __iter__(self) -> Iterator[_T]:
        for item in self._iterator:
            yield item

    def _iter_events(self) -> Iterator[ServerSentEvent]:
        yield from self._decoder.iter_bytes(self.response.iter_bytes())

    def __stream__(self) -> Iterator[_T]:
        for sse in self._iter_events():
            yield process_data(data=sse.json(), cast_to=cast_to, response=response)
```

Key features:
- Context manager support (`__enter__`/`__exit__`)
- Type-safe iteration with generic `_T`
- Lazy evaluation via Python generators
- Automatic connection cleanup on close

#### AsyncStream[T] (Asynchronous)

```python
class AsyncStream(Generic[_T]):
    """Provides the core interface to iterate over an asynchronous stream response."""

    async def __aiter__(self) -> AsyncIterator[_T]:
        async for item in self._iterator:
            yield item

    async def _iter_events(self) -> AsyncIterator[ServerSentEvent]:
        async for sse in self._decoder.aiter_bytes(self.response.aiter_bytes()):
            yield sse
```

Key features:
- Full async/await support with `__aiter__`/`__anext__`
- Async context manager (`__aenter__`/`__aexit__`)
- Non-blocking iteration for concurrent workloads

### 2.2 Tinker Python SDK: SSE/Chunked Encoding Parsing

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_streaming.py` (lines 148-302)

#### ServerSentEvent Struct

```python
class ServerSentEvent:
    def __init__(self, *, event: str | None, data: str | None, id: str | None, retry: int | None):
        self._id = id
        self._data = data or ""
        self._event = event or None
        self._retry = retry

    def json(self) -> Any:
        return json.loads(self.data)
```

#### SSEDecoder

The decoder implements the full SSE specification (https://html.spec.whatwg.org/multipage/server-sent-events.html):

```python
class SSEDecoder:
    _data: list[str]
    _event: str | None
    _retry: int | None
    _last_event_id: str | None

    def iter_bytes(self, iterator: Iterator[bytes]) -> Iterator[ServerSentEvent]:
        """Given an iterator that yields raw binary data, iterate over it & yield every event encountered"""
        for chunk in self._iter_chunks(iterator):
            for raw_line in chunk.splitlines():
                line = raw_line.decode("utf-8")
                sse = self.decode(line)
                if sse:
                    yield sse

    def _iter_chunks(self, iterator: Iterator[bytes]) -> Iterator[bytes]:
        """Given an iterator that yields raw binary data, iterate over it and yield individual SSE chunks"""
        data = b""
        for chunk in iterator:
            for line in chunk.splitlines(keepends=True):
                data += line
                if data.endswith((b"\r\r", b"\n\n", b"\r\n\r\n")):
                    yield data
                    data = b""
        if data:
            yield data

    def decode(self, line: str) -> ServerSentEvent | None:
        # Handles: event, data, id, retry fields per SSE spec
        # Handles comment lines (starting with :)
        # Handles multi-line data accumulation
```

Key SSE parsing features:
- Chunk boundary detection (`\r\r`, `\n\n`, `\r\n\r\n`)
- UTF-8 decoding
- Multi-line data field accumulation
- Event ID persistence (per SSE spec: "do not reset last_event_id")
- Comment line filtering (lines starting with `:`)
- Retry interval parsing

### 2.3 Tinker Python SDK: Future/Promise Patterns

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/futures.py`

The Python SDK provides a minimal futures resource:

```python
class AsyncFuturesResource(AsyncAPIResource):
    async def retrieve(
        self,
        *,
        request: FutureRetrieveRequest,
        extra_headers: Headers | None = None,
        timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
        idempotency_key: str | None = None,
        max_retries: int | NotGiven = NOT_GIVEN,
    ) -> FutureRetrieveResponse:
        """Retrieves the result of a future by its ID"""
        return await self._post(
            "/api/v1/retrieve_future",
            body=model_dump(request, exclude_unset=True, mode="json"),
            options=options,
            cast_to=FutureRetrieveResponse,
        )
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/shared/untyped_api_future.py`

```python
class UntypedAPIFuture(BaseModel):
    request_id: RequestID
    model_id: Optional[ModelID] = None
```

The Python SDK's future pattern is simple - it just provides retrieval. The sophisticated polling logic lives in the Tinkex Elixir implementation.

### 2.4 Tinker Python SDK: Async Client Patterns

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py`

```python
class AsyncTinker(AsyncAPIClient):
    @cached_property
    def with_streaming_response(self) -> AsyncTinkerWithStreamedResponse:
        return AsyncTinkerWithStreamedResponse(self)

class AsyncTinkerWithStreamedResponse:
    """Wrapper providing streaming response variants for all resources"""
    @cached_property
    def sampling(self) -> sampling.AsyncSamplingResourceWithStreamingResponse:
        return AsyncSamplingResourceWithStreamingResponse(self._client.sampling)
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` (lines 893-1045)

The base client's `request` method supports streaming:

```python
async def request(
    self,
    cast_to: Type[ResponseT],
    options: FinalRequestOptions,
    *,
    stream: bool = False,
    stream_cls: type[_AsyncStreamT] | None = None,
) -> ResponseT | _AsyncStreamT:
    # ...
    response = await self._client.send(
        request,
        stream=stream or self._should_stream_response_body(request=request),
        **kwargs,
    )
    # ...
    return await self._process_response(
        cast_to=cast_to, options=options, response=response,
        stream=stream, stream_cls=stream_cls, retries_taken=retries_taken,
    )
```

Key async patterns:
- `stream: bool` flag controls httpx streaming mode
- `stream_cls` type parameter for custom stream types
- Retry with exponential backoff (`_sleep_for_retry` using `anyio.sleep`)
- Proper async context manager lifecycle

### 2.5 Tinkex Elixir: Existing Streaming Implementation

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

```elixir
defmodule Tinkex.Streaming.ServerSentEvent do
  defstruct [:event, :data, :id, :retry]

  @spec json(t()) :: term()
  def json(%__MODULE__{data: data}) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> data
    end
  end
end

defmodule Tinkex.Streaming.SSEDecoder do
  defstruct buffer: ""

  @spec feed(t(), binary()) :: {[ServerSentEvent.t()], t()}
  def feed(%__MODULE__{} = decoder, chunk) when is_binary(chunk) do
    data = decoder.buffer <> chunk
    {events, rest} = parse_events(data, [])
    {Enum.reverse(events), %__MODULE__{buffer: rest}}
  end
```

The Tinkex Elixir SSE decoder is **functionally equivalent** to the Python version:
- Stateful buffer for incomplete chunks
- Event boundary detection via regex (`~r/\r\n\r\n|\n\n|\r\r/`)
- Field parsing (event, data, id, retry)
- Comment line filtering
- Multi-line data accumulation

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/stream_response.ex`

```elixir
defmodule Tinkex.API.StreamResponse do
  @enforce_keys [:stream, :status, :headers, :method, :url]
  defstruct [:stream, :status, :headers, :method, :url, :elapsed_ms]

  @type t :: %__MODULE__{
    stream: Enumerable.t(),
    status: integer() | nil,
    headers: map(),
    method: atom(),
    url: String.t(),
    elapsed_ms: non_neg_integer() | nil
  }
end
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/sampling.ex`

```elixir
@spec sample_stream(map(), keyword()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
def sample_stream(request, opts) do
  # ... build request ...
  case Finch.request(finch_request, pool_name, receive_timeout: timeout) do
    {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
      stream = parse_sse_response(response_body)
      {:ok, stream}
    # ... error handling ...
  end
end

defp parse_sse_response(body) do
  {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), body <> "\n\n")
  events
  |> Stream.map(&parse_sse_event/1)
  |> Stream.reject(&is_nil/1)
end
```

### 2.6 Tinkex Elixir: Future/Polling Implementation

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`

Tinkex provides a **much more sophisticated** future implementation than the Python SDK:

```elixir
defmodule Tinkex.Future do
  @moduledoc """
  Client-side future abstraction responsible for polling server-side futures.
  """

  defmodule State do
    defstruct request_id: nil,
              request_payload: nil,
              prev_queue_state: nil,
              config: nil,
              observer: nil,
              sleep_fun: nil,
              http_timeout: nil,
              poll_timeout: :infinity,
              poll_backoff: :none,
              start_time_ms: nil,
              last_failed_error: nil
  end

  @spec poll(String.t() | map(), keyword()) :: poll_task()
  def poll(request_or_payload, opts \\ []) do
    Task.async(fn -> poll_loop(state, 0) end)
  end

  defp poll_loop(state, iteration) do
    case ensure_within_timeout(state) do
      {:error, error} -> {:error, error}
      :ok -> do_poll(state, iteration)
    end
  end

  defp do_poll(state, iteration) do
    case Futures.retrieve(state.request_payload, ...) do
      {:ok, response} -> handle_response(FutureRetrieveResponse.from_json(response), state, iteration)
      {:error, %Error{status: 408}} -> retry_with_optional_backoff(state, iteration)
      {:error, %Error{status: status}} when status >= 500 -> retry_with_optional_backoff(state, iteration)
      {:error, %Error{type: :api_connection}} -> sleep_and_continue(state, calc_backoff(iteration), iteration)
      {:error, %Error{}} -> {:error, error}
    end
  end
```

Key features not in Python SDK:
- Task-based async polling
- Configurable poll timeouts
- Exponential backoff with jitter (via Foundation.Backoff)
- Queue state telemetry (`:tinkex, :queue, :state_change`)
- Observer callbacks for queue state transitions
- Distinction between retriable (5xx, 408) and non-retriable errors
- TryAgainResponse handling with server-specified retry delays

---

## 3. Pristine Equivalent: Current State

### 3.1 Transport Port

**Source**: `/home/home/p/g/n/pristine/lib/pristine/ports/transport.ex`

```elixir
defmodule Pristine.Ports.Transport do
  @callback send(Request.t(), Context.t()) :: {:ok, Response.t()} | {:error, term()}
end
```

The transport port is **synchronous request/response only**:
- No streaming callback
- No chunked response handling
- No SSE support
- No async variants

### 3.2 Finch Adapter

**Source**: `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex`

```elixir
defmodule Pristine.Adapters.Transport.Finch do
  @impl true
  def send(%Request{} = request, %Context{} = context) do
    case Finch.request(req, finch) do
      {:ok, response} ->
        {:ok, %Response{
          status: response.status,
          headers: Enum.into(response.headers, %{}),
          body: response.body
        }}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

Uses `Finch.request/2` which:
- Waits for full response body
- No `Finch.stream/4` usage
- No chunked transfer encoding support

### 3.3 Response Structure

**Source**: `/home/home/p/g/n/pristine/lib/pristine/core/response.ex`

```elixir
defmodule Pristine.Core.Response do
  defstruct status: nil, headers: %{}, body: nil, metadata: %{}

  @type t :: %__MODULE__{
    status: integer() | nil,
    headers: map(),
    body: binary() | nil,
    metadata: map()
  }
end
```

`body` is `binary() | nil` - assumes complete response, no streaming.

### 3.4 Pipeline

**Source**: `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`

```elixir
def execute(%Manifest{} = manifest, endpoint_id, payload, %Context{} = context, opts \\ []) do
  with {:ok, {body, content_type}} <- encode_body(...),
       request <- build_request(...),
       result <- retry.with_retry(fn -> transport.send(request, context) end, ...),
       {:ok, %Response{} = response} <- normalize_transport_result(result),
       decoded <- serializer.decode(response.body, response_schema, opts) do
    {:ok, data}
  end
end
```

Pipeline is **fully synchronous**:
- No streaming mode
- No future/promise handling
- No polling loop
- Complete response expected before decoding

### 3.5 Context Structure

**Source**: `/home/home/p/g/n/pristine/lib/pristine/core/context.ex`

No streaming-related configuration:
- No `stream_decoder` option
- No `sse_parser` option
- No `poll_config` option
- No `future_handler` option

---

## 4. Gap Analysis

### 4.1 Critical Gaps

| Capability | Tinker Python | Tinkex Elixir | Pristine | Gap Severity |
|------------|---------------|---------------|----------|--------------|
| SSE Decoder | Full spec | Full spec | **None** | Critical |
| Stream Iterator | `Stream[T]`/`AsyncStream[T]` | `Enumerable.t()` | **None** | Critical |
| Chunked Response | `iter_bytes()` | `Finch.stream/4` usage | **None** | Critical |
| Future Polling | Simple retrieve | Full polling + backoff | **None** | Critical |
| Streaming Transport | `stream=True` | `stream_get/2` | **None** | Critical |
| Stream Response Type | Generic typed | `StreamResponse.t()` | **None** | Critical |

### 4.2 Missing Components

1. **`Pristine.Ports.StreamTransport`** - Streaming transport behavior
2. **`Pristine.Streaming.SSEDecoder`** - SSE event parser
3. **`Pristine.Streaming.Event`** - SSE event struct
4. **`Pristine.Core.StreamResponse`** - Streaming response wrapper
5. **`Pristine.Ports.Future`** - Future/polling behavior
6. **`Pristine.Adapters.Future.Polling`** - Polling implementation
7. **`Pristine.Adapters.Transport.FinchStream`** - Streaming Finch adapter

### 4.3 Architectural Implications

1. **Transport Port Extension**: Current `send/2` callback insufficient for streaming. Need either:
   - New `stream/2` callback returning `Enumerable.t()`
   - Separate `StreamTransport` port

2. **Response Type Bifurcation**: `Response.t()` assumes complete body. Streaming needs:
   - `StreamResponse.t()` with `stream: Enumerable.t()`
   - Or polymorphic response with `body: binary() | Enumerable.t()`

3. **Pipeline Streaming Path**: `execute/5` needs streaming variant:
   - `execute_stream/5` returning `{:ok, Enumerable.t()}`
   - Or `stream: true` option in existing execute

4. **Future Port**: Polling is fundamentally different from request/response:
   - Long-lived async operation
   - Telemetry for queue state
   - Configurable backoff policies
   - Observer callbacks

---

## 5. Recommended Changes

### 5.1 Phase 1: SSE Infrastructure (Priority: High)

**New Files:**

```
lib/pristine/streaming/
  event.ex              # ServerSentEvent struct
  sse_decoder.ex        # Stateful SSE parser
```

**Port from Tinkex**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

The Tinkex SSE decoder is well-tested and spec-compliant. Direct port with Pristine namespacing.

### 5.2 Phase 2: Streaming Transport (Priority: High)

**New Port:**

```elixir
# lib/pristine/ports/stream_transport.ex
defmodule Pristine.Ports.StreamTransport do
  @callback stream(Request.t(), Context.t()) ::
    {:ok, StreamResponse.t()} | {:error, term()}
end
```

**New Response Type:**

```elixir
# lib/pristine/core/stream_response.ex
defmodule Pristine.Core.StreamResponse do
  defstruct [:stream, :status, :headers, :metadata]

  @type t :: %__MODULE__{
    stream: Enumerable.t(),
    status: integer(),
    headers: map(),
    metadata: map()
  }
end
```

**New Adapter:**

```elixir
# lib/pristine/adapters/transport/finch_stream.ex
defmodule Pristine.Adapters.Transport.FinchStream do
  @behaviour Pristine.Ports.StreamTransport

  @impl true
  def stream(%Request{} = request, %Context{} = context) do
    # Use Finch.stream/4 with SSE decoder callback
  end
end
```

### 5.3 Phase 3: Streaming Pipeline (Priority: Medium)

**Extend Context:**

```elixir
# Add to Pristine.Core.Context
defstruct [
  # ... existing fields ...
  stream_decoder: nil,       # SSE decoder module
  stream_parser: nil,        # Event parser function
]
```

**New Pipeline Function:**

```elixir
# lib/pristine/core/pipeline.ex
@spec execute_stream(Manifest.t(), atom(), term(), Context.t(), keyword()) ::
  {:ok, Enumerable.t()} | {:error, term()}
def execute_stream(manifest, endpoint_id, payload, context, opts \\ []) do
  # Similar to execute/5 but uses stream_transport and returns StreamResponse
end
```

### 5.4 Phase 4: Future/Polling Port (Priority: Medium)

**New Port:**

```elixir
# lib/pristine/ports/future.ex
defmodule Pristine.Ports.Future do
  @callback poll(request_id :: String.t(), Context.t(), keyword()) ::
    {:ok, Task.t()} | {:error, term()}

  @callback await(Task.t(), timeout()) ::
    {:ok, term()} | {:error, term()}
end
```

**Port from Tinkex**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`

The Tinkex Future module is sophisticated - consider direct port with Pristine adapter pattern.

### 5.5 Phase 5: Queue State Telemetry (Priority: Low)

**Port telemetry patterns from Tinkex:**
- `[:pristine, :queue, :state_change]` event
- Observer behavior for state transitions
- Integration with existing `Pristine.Adapters.Telemetry.Reporter`

---

## 6. Concrete Next Steps (TDD Approach)

### Step 1: SSE Decoder Tests (Day 1)

```elixir
# test/pristine/streaming/sse_decoder_test.exs
defmodule Pristine.Streaming.SSEDecoderTest do
  test "parses complete SSE event" do
    chunk = "event: message\ndata: {\"foo\":\"bar\"}\n\n"
    {events, decoder} = SSEDecoder.feed(SSEDecoder.new(), chunk)
    assert [%Event{event: "message", data: ~s({"foo":"bar"})}] = events
  end

  test "handles chunked delivery" do
    {[], decoder} = SSEDecoder.feed(SSEDecoder.new(), "data: par")
    {events, _} = SSEDecoder.feed(decoder, "tial\n\n")
    assert [%Event{data: "partial"}] = events
  end

  test "parses multi-line data" do
    chunk = "data: line1\ndata: line2\n\n"
    {[event], _} = SSEDecoder.feed(SSEDecoder.new(), chunk)
    assert event.data == "line1\nline2"
  end
end
```

### Step 2: SSE Decoder Implementation (Day 1)

Port from `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex` with Pristine namespacing.

### Step 3: StreamTransport Port Tests (Day 2)

```elixir
# test/pristine/ports/stream_transport_test.exs
defmodule Pristine.Ports.StreamTransportTest do
  test "stream/2 returns StreamResponse with enumerable" do
    {:ok, response} = MockTransport.stream(request, context)
    assert %StreamResponse{stream: stream} = response
    assert Enum.take(stream, 1) |> length() == 1
  end
end
```

### Step 4: FinchStream Adapter (Day 2-3)

```elixir
# lib/pristine/adapters/transport/finch_stream.ex
defmodule Pristine.Adapters.Transport.FinchStream do
  alias Pristine.Streaming.SSEDecoder

  def stream(request, context) do
    ref = Finch.request(req, finch, receive_timeout: timeout)
    stream = build_event_stream(ref, SSEDecoder.new())
    {:ok, %StreamResponse{stream: stream, status: status, headers: headers}}
  end
end
```

### Step 5: Future Port Tests (Day 3-4)

```elixir
# test/pristine/ports/future_test.exs
defmodule Pristine.Ports.FutureTest do
  test "poll/3 returns async task" do
    {:ok, task} = FutureAdapter.poll("req-123", context, [])
    assert %Task{} = task
  end

  test "await/2 returns result on completion" do
    {:ok, task} = FutureAdapter.poll("req-123", context, [])
    {:ok, result} = FutureAdapter.await(task, 5000)
    assert result["status"] == "completed"
  end
end
```

### Step 6: Pipeline Streaming Integration (Day 4-5)

```elixir
# test/pristine/core/pipeline_stream_test.exs
defmodule Pristine.Core.PipelineStreamTest do
  test "execute_stream returns event enumerable" do
    {:ok, stream} = Pipeline.execute_stream(manifest, :stream_endpoint, payload, context)
    events = Enum.to_list(stream)
    assert length(events) > 0
  end
end
```

---

## 7. File References

### Tinker Python SDK (Source)
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_streaming.py` - Core streaming classes
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` - Async client base
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` - AsyncTinker client
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/futures.py` - Futures resource
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/shared/untyped_api_future.py` - Future type

### Tinkex Elixir (Reference Implementation)
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex` - SSE decoder
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/stream_response.ex` - Stream response type
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/sampling.ex` - Streaming API usage
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/api.ex` - stream_get implementation
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex` - Future polling
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/futures.ex` - Futures API
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sample_stream_chunk.ex` - Stream chunk type

### Pristine (Target - Current State)
- `/home/home/p/g/n/pristine/lib/pristine/ports/transport.ex` - Transport port (needs extension)
- `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex` - Finch adapter (non-streaming)
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex` - Pipeline (synchronous only)
- `/home/home/p/g/n/pristine/lib/pristine/core/response.ex` - Response type (non-streaming)
- `/home/home/p/g/n/pristine/lib/pristine/core/context.ex` - Context (no streaming config)

---

## 8. Conclusion

Pristine lacks all streaming, SSE, and future/polling capabilities present in the Tinker SDK ecosystem. The Tinkex Elixir implementation provides a proven reference that can be ported with relatively low risk:

1. **SSE Decoder**: Direct port from Tinkex (~130 lines)
2. **Stream Transport**: New port + Finch.stream adapter
3. **Future Polling**: Port Tinkex.Future module (~575 lines)
4. **Pipeline Integration**: Extend existing pipeline with streaming path

Estimated effort: **5-7 days** for complete streaming infrastructure with TDD.
