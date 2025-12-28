# Streaming and Async Patterns Analysis for Tinker Python SDK

## 1. SSE (Server-Sent Events) Streaming Architecture

**Key Files**: `/tinker/src/tinker/_streaming.py`

The Tinker SDK implements Server-Sent Event streaming with two main classes:

**Stream** (Synchronous):
- Generic class wrapping `httpx.Response` for synchronous iteration
- Uses `SSEBytesDecoder` to parse incoming byte chunks
- Implements iterator protocol (`__iter__`, `__next__`)
- Context manager support (`__enter__`, `__exit__`)
- Resource cleanup via `close()` method

**AsyncStream** (Asynchronous):
- Mirror of Stream but for async contexts
- Implements async iterator protocol (`__aiter__`, `__anext__`)
- Async context manager support (`__aenter__`, `__aexit__`)
- Resource cleanup via async `close()` method

**Critical Pattern**: Both classes accept `cast_to: type[_T]` parameter to deserialize stream chunks into typed objects.

---

## 2. SSE Event Parsing and Accumulation

**ServerSentEvent** class structure:
```python
- event: str | None      # Event type identifier
- data: str              # JSON string payload
- id: str | None         # Last Event ID (persists across reconnects)
- retry: int | None      # Milliseconds to wait before retry
```

**SSEDecoder** class provides stateful parsing:
- Maintains internal state: `_event`, `_data[]`, `_event_id`, `_retry`
- Implements [WHATWG EventSource spec](https://html.spec.whatwg.org/multipage/server-sent-events.html) compliance
- Accumulates multi-line data fields with newline joining
- Chunk detection: responds to `\r\r`, `\n\n`, `\r\n\r\n` separators
- Method: `iter_bytes()` (sync), `aiter_bytes()` (async)

> **Note**: SSE follows the WHATWG EventSource spec, not RFC 6202 (which is an
> informational document about bidirectional HTTP, not SSE).

**Event Lifecycle**:
1. Reads byte chunks from response
2. Buffers incomplete lines
3. Detects chunk boundaries (double newlines)
4. Parses field lines (`field: value`)
5. Accumulates multi-line data fields
6. Emits complete `ServerSentEvent` on empty line
7. Resets state (except `last_event_id`)

---

## 3. Stream Lifecycle Management

**Initialization**:
```python
Stream.__init__ receives:
- cast_to: type[_T]          # Type for deserializing chunks
- response: httpx.Response   # Active HTTP response
- client: Tinker/AsyncTinker # Client for SSE decoder config
```

**Active State**:
- `_iterator` holds the generator created by `__stream__()`
- Decoder continuously consumes `response.iter_bytes()` or `response.aiter_bytes()`
- Each chunk processed line-by-line through stateful decoder

**Graceful Shutdown**:
```python
def close(self):
    self.response.close()

async def close(self):  # AsyncStream version
    await self.response.aclose()
```

**Important**: After yielding all items, the stream consumes remaining iterator to ensure proper cleanup.

---

## 4. Error Handling in Streams

**At SSE Level**:
- `ServerSentEvent.json()` calls `json.loads(self.data)` - can raise `JSONDecodeError`
- UTF-8 decoding: handled by httpx transport layer before reaching decoder
- Lines starting with `:` (comments) are silently ignored per WHATWG spec

**At Stream Level**:
- Exceptions in `_process_response_data()` propagate to caller
- `response.close()` exceptions not explicitly handled (relies on httpx)
- Context managers ensure cleanup even on exception

**At SSEDecoder Level**:
- Null bytes in event ID silently rejected
- Invalid retry values silently ignored
- Field names not matching spec silently ignored

---

## 5. Integration with Client

**Client Methods** (`_base_client.py`):

1. **`_make_sse_decoder()`**: Returns fresh `SSEDecoder()` instance
   - Called once per stream in `Stream.__init__`
   - Can be overridden for custom decoding

2. **`_process_response_data()`**: Validates and constructs response objects
   - Accepts raw JSON data from SSE
   - Handles `ModelBuilderProtocol` types
   - Performs Pydantic validation
   - Can raise `APIResponseValidationError` on invalid data

3. **`_should_stream_response_body()`**: Checks for `RAW_RESPONSE_HEADER == "stream"`
   - Routes response to Stream vs normal response handling

**Stream Detection Pattern**:
- Client checks response headers
- If streaming, returns `Stream[T]` or `AsyncStream[T]` instead of unwrapped response

---

## 6. Futures and Async Polling Architecture

**Key Files**:
- `/tinker/lib/api_future_impl.py`
- `/tinker/lib/public_interfaces/api_future.py`

**APIFuture Abstract Interface**:
```python
class APIFuture(ABC, Generic[T]):
    async def result_async(timeout: float | None = None) -> T
    def result(timeout: float | None = None) -> T  # Sync wrapper
    def __await__() -> enables: await api_future
```

**_APIFuture Implementation** - Polling Strategy:

1. **Initialization**:
   - Captures `untyped_future: UntypedAPIFuture` (contains `request_id`)
   - Records `request_start_time` for telemetry
   - Launches background `_result_async()` coroutine immediately
   - Wraps in concurrent.futures.Future for sync access

2. **Polling Loop** (`_result_async` method):
```python
Infinite retry loop with:
- Iteration tracking (increments on each attempt)
- Timeout enforcement (raises TimeoutError)
- Exponential backoff for connection errors
- Status code inspection for retry decisions
```

3. **Retry Strategy**:
   - **408 (Request Timeout)**: Continue polling (queue may be busy)
   - **410 (Gone)**: Raise RetryableException (future expired)
   - **500-599 (Server Error)**: Continue polling with backoff
   - **4xx (User Error)**: Raise immediately
   - Connection errors: Exponential backoff up to 30 seconds

4. **Result Types**:
   - `TryAgainResponse`: Triggers retry
   - `RequestFailedResponse`: Raises RequestFailedError
   - `ForwardBackwardOutput`, `OptimStepResponse`, etc.: Returned to caller
   - Results cached in `_cached_result` (sentinel: `_UNCOMPUTED`)

---

## 7. Queue State Observation

**Pattern in _APIFuture**:
- Accepts optional `queue_state_observer: QueueStateObserver`
- On 408 response, parses `queue_state` from response body
- States: ACTIVE, PAUSED_RATE_LIMIT, PAUSED_CAPACITY, UNKNOWN
- Notifies observer via `on_queue_state_change()` callback

---

## 8. Telemetry Integration

**Captured in Future Polling**:
- `X-Tinker-Request-Iteration`: Current retry attempt
- `X-Tinker-Request-Type`: Request operation type
- `X-Tinker-Create-Promise-Roundtrip-Time`: First-call latency (header only)

**Logged Events**:
- `APIFuture.result_async.timeout`: When timeout exceeded
- `APIFuture.result_async.api_status_error`: HTTP errors with retry decision
- `APIFuture.result_async.connection_error`: Network issues
- `APIFuture.result_async.application_error`: Server-side errors
- `APIFuture.result_async.validation_error`: Response parsing failures

**Telemetry Payload**:
```python
{
    "request_id": str,
    "request_type": str,
    "status_code": int,
    "iteration": int,
    "elapsed_time": float,
    "exception": str,
    "should_retry": bool,
    "is_user_error": bool,
    "severity": "INFO" | "WARNING" | "ERROR"
}
```

---

## 9. Combined Futures Pattern

**_CombinedAPIFuture** for batch operations:
```python
class _CombinedAPIFuture(APIFuture[T]):
    def __init__(
        self,
        futures: List[APIFuture[T]],
        transform: Callable[[List[T]], T],
        holder: InternalClientHolder
    )

    async def result_async(timeout: float | None = None) -> T:
        results = await asyncio.gather(
            *[future.result_async(timeout) for future in self.futures]
        )
        return self.transform(results)
```

- Uses `asyncio.gather()` for parallel future resolution
- Applies transformation function to collected results
- Single timeout applies to entire batch

---

## 10. Sync/Async Bridge Pattern

**Dual-Mode Access**:
```python
future = client.some_operation()  # Returns APIFuture[T]

# Async usage
result = await future
result = await future.result_async()

# Sync usage
result = future.result()  # Blocks via concurrent.futures
```

**Implementation**:
- `_APIFuture.__init__`: Calls `holder.run_coroutine_threadsafe(_result_async())`
- Returns `AwaitableConcurrentFuture` wrapping concurrent.futures.Future
- `__await__` delegates to `result_async()`

---

## 11. Key Features Pristine Must Support

### Streaming Essentials:
1. HTTP response streaming with progressive event delivery
2. SSE format parsing (WHATWG EventSource spec compliant)
3. Line-based protocol with double-newline delimiters
4. Stateful event accumulation across chunks
5. JSON deserialization of event data
6. Type casting of stream items
7. Resource cleanup (connection release)
8. Both synchronous and asynchronous iteration

### Async Polling Essentials:
1. Long-running request polling with request_id
2. Configurable retry strategy (408, 500-599 retries)
3. Exponential backoff for connection errors
4. Request timeout enforcement
5. Structured error responses (try_again, error with category)
6. Queue state observation callbacks
7. Telemetry instrumentation (headers + event logging)
8. Result caching
9. Sync/async dual-mode access
10. Combined futures with transformation functions
11. Context manager support for streams
12. Graceful shutdown and resource cleanup

---

## 12. Critical Implementation Details

1. **Stateful Decoder**: SSEDecoder maintains state across calls - can't be shared or reset unexpectedly
2. **Last Event ID Persistence**: Never reset after event emission (per WHATWG spec)
3. **Multi-line Data Fields**: Multiple `data:` lines joined with newlines
4. **Telemetry Headers**: Must be added on EVERY polling attempt (not just first)
5. **Cached Results**: Prevent re-polling after first success
6. **Connection Pool**: Uses `ClientConnectionPoolType` enum (RETRIEVE_PROMISE, TELEMETRY, etc.)
7. **Model Validation**: Leverages BaseModel.model_validate() or construct_type() fallback
8. **Thread Safety**: Telemetry components use locks for cross-thread access

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinker Python SDK streaming and futures modules*
