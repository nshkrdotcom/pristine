# Transport, Retry, and Telemetry Architecture Audit

**Date**: 2025-12-28
**Scope**: Mapping Tinker Python SDK transport/retry/telemetry patterns to Pristine adapters and Foundation library

---

## 1. Summary

### What Tinker's Transport/Retry/Telemetry Does

The **Tinker Python SDK** provides a comprehensive client-side resilience and observability stack:

1. **Transport Layer** (`_base_client.py`): HTTP client built on `httpx` with:
   - Async-first design with HTTP/2 support
   - Automatic retry logic with exponential backoff
   - Request/response type coercion and validation
   - Streaming support (SSE)

2. **Retry Handler** (`lib/retry_handler.py`): A generalizable retry wrapper with:
   - Connection limiting via semaphores
   - Global progress timeout tracking ("straggler detection")
   - Exponential backoff with configurable jitter
   - Telemetry integration for exception tracking

3. **Telemetry System** (`lib/telemetry.py`): Client-side analytics and diagnostics:
   - Session-scoped event batching
   - Automatic session start/end events
   - Exception capture with user-error classification
   - Periodic flush with retry-on-failure

---

## 2. Detailed Analysis

### 2.1 Retry Strategies and Configuration

#### Tinker Python SDK (Source)

**File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/retry_handler.py`

```python
@dataclass
class RetryConfig:
    max_connections: int = 100           # Semaphore limit
    progress_timeout: float = 120 * 60   # 2 hours (straggler timeout)
    retry_delay_base: float = 0.5        # Initial delay (seconds)
    retry_delay_max: float = 10.0        # Max delay cap (seconds)
    jitter_factor: float = 0.25          # +/- 25% jitter
    enable_retry_logic: bool = True
    retryable_exceptions: tuple = (
        asyncio.TimeoutError,
        tinker.APIConnectionError,
        httpx.TimeoutException,
        RetryableException,
    )
```

**Key Behaviors**:
- Retries on: `408`, `409`, `429`, and `5xx` status codes
- Respects `x-should-retry` header from server
- Respects `Retry-After` and `retry-after-ms` headers
- No hard attempt limit (time-bounded via progress timeout)

**File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` (lines 683-706)

```python
def _calculate_retry_timeout(self, remaining_retries, options, response_headers):
    retry_after = self._parse_retry_after_header(response_headers)
    if retry_after is not None and 0 < retry_after <= 60:
        return retry_after

    nb_retries = min(max_retries - remaining_retries, 1000)
    sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)
    jitter = 1 - 0.25 * random()
    return max(0, sleep_seconds * jitter)
```

**File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_constants.py`

```python
DEFAULT_MAX_RETRIES = 10
INITIAL_RETRY_DELAY = 0.5
MAX_RETRY_DELAY = 10.0
```

#### Tinkex Elixir (Existing Port)

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_config.ex`

```elixir
defstruct [
  max_retries: :infinity,          # Matches Python's time-bounded approach
  base_delay_ms: 500,              # 0.5 seconds
  max_delay_ms: 10_000,            # 10 seconds
  jitter_pct: 0.25,                # 25% jitter
  progress_timeout_ms: 7_200_000,  # 2 hours (120 * 60 * 1000)
  max_connections: 1_000,
  enable_retry_logic: true
]
```

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry.ex`

```elixir
defp build_policy(%RetryHandler{} = handler) do
  backoff = Backoff.Policy.new(
    strategy: :exponential,
    base_ms: handler.base_delay_ms,
    max_ms: handler.max_delay_ms,
    jitter_strategy: :range,
    jitter: {1.0 - handler.jitter_pct, 1.0 + handler.jitter_pct}
  )

  FoundationRetry.Policy.new(
    max_attempts: handler.max_retries,
    progress_timeout_ms: handler.progress_timeout_ms,
    backoff: backoff,
    retry_on: &retryable_result?/1
  )
end
```

#### Pristine Elixir (Target)

**File**: `/home/home/p/g/n/pristine/lib/pristine/ports/retry.ex`

```elixir
defmodule Pristine.Ports.Retry do
  @callback with_retry((-> term()), keyword()) :: term()
end
```

**File**: `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex`

```elixir
def with_retry(fun, opts) when is_function(fun, 0) do
  policy = normalize_policy(opts)
  {result, _state} = Retry.run(fun, policy)
  result
end
```

#### Foundation Library

**File**: `/home/home/p/g/n/foundation/lib/foundation/retry.ex`

```elixir
defmodule Foundation.Retry.Policy do
  defstruct max_attempts: 0,
            max_elapsed_ms: nil,
            backoff: nil,
            retry_on: nil,
            progress_timeout_ms: nil,
            retry_after_ms_fun: nil
end
```

**Capabilities**:
- Configurable `max_attempts` (supports `:infinity`)
- `max_elapsed_ms` - total time budget
- `progress_timeout_ms` - straggler detection
- `retry_after_ms_fun` - custom delay function (for Retry-After headers)
- Pluggable `retry_on` predicate

---

### 2.2 Backoff Algorithms

#### Tinker Python SDK

```python
# _base_client.py lines 699-705
sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)
jitter = 1 - 0.25 * random()
timeout = sleep_seconds * jitter
```

**Algorithm**: Exponential backoff with multiplicative jitter (0.75x to 1.0x).

#### Tinkex Elixir

```elixir
# retry.ex lines 136-143
backoff = Backoff.Policy.new(
  strategy: :exponential,
  base_ms: handler.base_delay_ms,
  max_ms: handler.max_delay_ms,
  jitter_strategy: :range,
  jitter: {1.0 - handler.jitter_pct, 1.0 + handler.jitter_pct}
)
```

**Algorithm**: Exponential backoff with range jitter (0.75x to 1.25x).

#### Foundation Library

**File**: `/home/home/p/g/n/foundation/lib/foundation/backoff.ex`

```elixir
defmodule Foundation.Backoff.Policy do
  @type strategy :: :exponential | :linear | :constant
  @type jitter_strategy :: :none | :factor | :additive | :range

  defstruct strategy: :exponential,
            base_ms: 1_000,
            max_ms: 10_000,
            jitter_strategy: :none,
            jitter: 0.0,
            rand_fun: &:rand.uniform/0
end
```

**Supported Strategies**:
- `:exponential` - `base_ms * 2^attempt`
- `:linear` - `base_ms * (attempt + 1)`
- `:constant` - `base_ms`

**Jitter Strategies**:
- `:none` - no jitter
- `:factor` - multiplicative factor
- `:additive` - add random amount
- `:range` - multiply by factor in `{min, max}` range

---

### 2.3 Circuit Breaker Patterns

#### Tinker Python SDK

The Python SDK does **not** implement circuit breakers. Retry logic is per-request without cross-request state sharing.

#### Tinkex Elixir

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker.ex`

Wraps `Foundation.CircuitBreaker` with a Tinkex-specific struct shape:

```elixir
defstruct [
  :name,
  :opened_at,
  state: :closed,
  failure_count: 0,
  failure_threshold: 5,
  reset_timeout_ms: 30_000,
  half_open_max_calls: 1,
  half_open_calls: 0
]
```

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker/registry.ex`

ETS-based registry for per-endpoint circuit breaker state:

```elixir
def call(name, fun, opts \\ []) do
  FoundationRegistry.call(@table_name, name, fun, opts)
end
```

#### Foundation Library

**File**: `/home/home/p/g/n/foundation/lib/foundation/circuit_breaker.ex`

Standard three-state circuit breaker:

| State | Behavior |
|-------|----------|
| `:closed` | Requests pass through, failures counted |
| `:open` | All requests rejected, wait for timeout |
| `:half_open` | Limited requests allowed to test recovery |

```elixir
@spec call(t(), (-> result), keyword()) :: {result | {:error, :circuit_open}, t()}
def call(%__MODULE__{} = cb, fun, opts \\ []) when is_function(fun, 0) do
  case state(cb) do
    :open -> {{:error, :circuit_open}, cb}
    current_state ->
      result = fun.()
      if success_fn.(result) do
        {result, record_success(cb)}
      else
        {result, record_failure(cb)}
      end
  end
end
```

**File**: `/home/home/p/g/n/foundation/lib/foundation/circuit_breaker/registry.ex`

ETS-based registry with CAS updates to prevent lost-update races:

```elixir
@spec call(registry(), String.t(), (-> result), keyword()) :: result | {:error, :circuit_open}
def call(registry, name, fun, opts) do
  {version, cb} = get_or_create(registry, name, opts)
  # ... execute and update with retry on version conflict
end
```

#### Pristine Elixir

**File**: `/home/home/p/g/n/pristine/lib/pristine/ports/circuit_breaker.ex`

```elixir
@callback call(String.t(), (-> term()), keyword()) :: term()
```

**File**: `/home/home/p/g/n/pristine/lib/pristine/adapters/circuit_breaker/foundation.ex`

```elixir
def call(name, fun, opts \\ []) when is_function(fun, 0) do
  registry = Keyword.get(opts, :registry, Registry.default_registry())
  Registry.call(registry, to_string(name), fun, opts)
end
```

---

### 2.4 Rate Limiting Approaches

#### Tinker Python SDK

**Connection Limiting** via `asyncio.Semaphore`:

```python
# retry_handler.py line 128
self._semaphore = asyncio.Semaphore(config.max_connections)

async def execute(self, func, *args, **kwargs):
    async with self._semaphore:
        # ...
```

**No server-side rate limit tracking** - relies on 429 responses and `Retry-After` header.

#### Tinkex Elixir

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/rate_limiter.ex`

Uses Foundation's `BackoffWindow` for per-client rate limiting:

```elixir
def for_key({base_url, api_key}) do
  normalized_base = PoolKey.normalize_base_url(base_url)
  key = {:limiter, {normalized_base, api_key}}
  BackoffWindow.for_key(registry(), key)
end
```

Connection limiting via Finch pools (not a separate semaphore).

#### Foundation Library

**File**: `/home/home/p/g/n/foundation/lib/foundation/rate_limit/backoff_window.ex`

ETS + atomics-based shared backoff windows:

```elixir
@spec should_backoff?(limiter(), keyword()) :: boolean()
def should_backoff?(limiter, opts \\ []) do
  backoff_until = :atomics.get(limiter, 1)
  backoff_until != 0 and time_fun.(:millisecond) < backoff_until
end

@spec set(limiter(), non_neg_integer(), keyword()) :: :ok
def set(limiter, duration_ms, opts \\ []) do
  backoff_until = time_fun.(:millisecond) + duration_ms
  :atomics.put(limiter, 1, backoff_until)
end
```

**Key Features**:
- Lock-free via `:atomics`
- ETS registry for key-based lookup
- Supports custom time/sleep functions for testing

#### Pristine Elixir

**File**: `/home/home/p/g/n/pristine/lib/pristine/ports/rate_limit.ex`

```elixir
@callback within_limit((-> term()), keyword()) :: term()
```

**File**: `/home/home/p/g/n/pristine/lib/pristine/adapters/rate_limit/backoff_window.ex`

```elixir
def within_limit(fun, opts) when is_function(fun, 0) do
  key = Keyword.get(opts, :key, :default)
  limiter = BackoffWindow.for_key(registry, key)

  if BackoffWindow.should_backoff?(limiter, opts) do
    BackoffWindow.wait(limiter, opts)
  end

  fun.()
end
```

---

### 2.5 Telemetry Events and Spans

#### Tinker Python SDK

**File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/telemetry.py`

**Event Types**:

| Event | Fields |
|-------|--------|
| `SESSION_START` | event_id, session_index, timestamp |
| `SESSION_END` | event_id, session_index, timestamp, duration |
| `GENERIC_EVENT` | event_id, session_index, timestamp, severity, event_name, event_data |
| `UNHANDLED_EXCEPTION` | event_id, session_index, timestamp, severity, error_type, error_message, traceback |

**Batching**:
```python
MAX_BATCH_SIZE = 100
FLUSH_INTERVAL = 10.0  # seconds
MAX_QUEUE_SIZE = 10000
```

**User Error Classification**:
```python
def is_user_error(exception):
    # 4xx errors (except 408, 429) are user errors
    status_code = getattr(exception, "status_code", None)
    if isinstance(status_code, int) and 400 <= status_code < 500 and status_code != 408:
        return True
    # RequestFailedError with User category
    if isinstance(exception, RequestFailedError) and exception.category is RequestErrorCategory.User:
        return True
    return False
```

#### Tinkex Elixir

**File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter.ex`

Full port of Python telemetry with:
- Same event types and batching
- GenServer-based queue management
- Foundation.Backoff for retry delays
- Exception cause chain traversal for user error detection

**Telemetry Events** (via `:telemetry` library):
```elixir
@default_events [
  [:tinkex, :http, :request, :start],
  [:tinkex, :http, :request, :stop],
  [:tinkex, :http, :request, :exception],
  [:tinkex, :queue, :state_change]
]
```

**Retry Telemetry**:
```elixir
# retry.ex
@telemetry_start [:tinkex, :retry, :attempt, :start]
@telemetry_stop [:tinkex, :retry, :attempt, :stop]
@telemetry_retry [:tinkex, :retry, :attempt, :retry]
@telemetry_failed [:tinkex, :retry, :attempt, :failed]
```

#### Foundation Library

**File**: `/home/home/p/g/n/foundation/lib/foundation/telemetry.ex`

Wrapper around `TelemetryService`:

```elixir
defdelegate execute(event_name, measurements, metadata), to: TelemetryService
defdelegate measure(event_name, metadata, fun), to: TelemetryService
defdelegate emit_counter(event_name, metadata), to: TelemetryService
defdelegate emit_gauge(event_name, value, metadata), to: TelemetryService
```

**Event Naming Convention**: `[:foundation, :category, :action]`

#### Pristine Elixir

**File**: `/home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex`

```elixir
@callback emit(atom(), map(), map()) :: :ok
```

**File**: `/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/reporter.ex`

```elixir
def emit(event, meta, meas) do
  TelemetryReporter.log(TelemetryReporter, to_string(event), %{meta: meta, meas: meas})
end
```

---

## 3. Pristine/Foundation Equivalent: Current Capabilities

### 3.1 Retry System

| Capability | Foundation | Pristine Port | Status |
|------------|------------|---------------|--------|
| Exponential backoff | Yes | Yes | Complete |
| Linear/constant backoff | Yes | Yes | Complete |
| Jitter (factor/additive/range) | Yes | Yes | Complete |
| Max attempts | Yes | Yes | Complete |
| Max elapsed time | Yes | Exposed | Complete |
| Progress timeout | Yes | Exposed | Complete |
| Custom retry predicate | Yes | Exposed | Complete |
| Retry-After header support | Yes (`retry_after_ms_fun`) | Not wired | Gap |

### 3.2 Circuit Breaker

| Capability | Foundation | Pristine Port | Status |
|------------|------------|---------------|--------|
| Three-state machine | Yes | Yes | Complete |
| ETS registry | Yes | Yes | Complete |
| CAS updates | Yes | Yes | Complete |
| Half-open probing | Yes | Yes | Complete |
| Custom success predicate | Yes | Exposed | Complete |
| Failure threshold config | Yes | Exposed | Complete |
| Reset timeout config | Yes | Exposed | Complete |

### 3.3 Rate Limiting

| Capability | Foundation | Pristine Port | Status |
|------------|------------|---------------|--------|
| Backoff windows | Yes | Yes | Complete |
| Lock-free atomics | Yes | Yes | Complete |
| ETS registry | Yes | Yes | Complete |
| Blocking wait | Yes | Yes | Complete |
| Connection semaphore | No | No | Gap |

### 3.4 Telemetry

| Capability | Foundation | Pristine Port | Status |
|------------|------------|---------------|--------|
| Event execution | Yes | Partial | Gap |
| Span measurement | Yes | No | Gap |
| Counter metrics | Yes | No | Gap |
| Gauge metrics | Yes | No | Gap |
| Handler attachment | Yes | No | Gap |
| Session batching | No | No | Gap |
| Backend reporting | No | No | Gap |

---

## 4. Gap Analysis

### 4.1 Critical Gaps

1. **Retry-After Header Parsing**
   - Foundation supports `retry_after_ms_fun` but Pristine doesn't expose it
   - HTTP 429 responses with Retry-After need to be respected

2. **Connection/Concurrency Limiting**
   - Python uses `asyncio.Semaphore` to limit concurrent connections
   - Foundation has `Semaphore.Counting` and `Semaphore.Weighted` but unused in Pristine
   - Important for preventing connection pool exhaustion

3. **Session-Scoped Telemetry**
   - Tinkex has full session batching/flushing to backend
   - Pristine only has local emit, no backend reporting
   - Missing: session start/end, exception capture, user error classification

4. **Telemetry Span Measurement**
   - Foundation has `measure/3` for timing functions
   - Pristine port doesn't expose this

### 4.2 Medium-Priority Gaps

1. **Graceful Degradation**
   - Foundation has `Config.GracefulDegradation` and `Events.GracefulDegradation`
   - Pristine has no equivalent for resilient fallback behavior

2. **Progress Logging**
   - Python RetryHandler logs progress periodically
   - Useful for debugging stalled operations

3. **Exception Telemetry**
   - Tinkex captures and classifies exceptions
   - Pristine has no exception-to-telemetry pipeline

### 4.3 Low-Priority Gaps

1. **Telemetry Toggle**
   - Tinkex respects `TINKER_TELEMETRY` env var
   - Pristine has no global disable mechanism

2. **Wait-Until-Drained**
   - Tinkex supports graceful shutdown with flush
   - Important for production deployments

---

## 5. Recommended Changes

### 5.1 Foundation Enhancements

#### 5.1.1 Add Retry-After Header Extraction Helper

```elixir
# foundation/lib/foundation/retry/http.ex (new file)
defmodule Foundation.Retry.HTTP do
  @doc """
  Extract retry delay from HTTP response headers.

  Supports:
  - `retry-after-ms` (milliseconds, non-standard but precise)
  - `retry-after` (seconds or HTTP date)
  """
  @spec parse_retry_after(map()) :: non_neg_integer() | nil
  def parse_retry_after(headers) do
    cond do
      ms = headers["retry-after-ms"] ->
        parse_integer(ms)

      seconds = headers["retry-after"] ->
        case parse_integer(seconds) do
          nil -> parse_http_date(seconds)
          ms -> ms * 1000
        end

      true -> nil
    end
  end
end
```

#### 5.1.2 Add Counting Semaphore to Rate Limiting

```elixir
# Already exists: foundation/lib/foundation/semaphore/counting.ex
# Need to expose in Pristine adapter
```

#### 5.1.3 Add Session-Scoped Telemetry Reporter

```elixir
# foundation/lib/foundation/telemetry/session_reporter.ex (new file)
defmodule Foundation.Telemetry.SessionReporter do
  @moduledoc """
  Session-scoped telemetry batching and backend reporting.

  Mirrors Tinkex.Telemetry.Reporter but without Tinker-specific types.
  """

  use GenServer

  defstruct [
    :session_id,
    :backend_url,
    :flush_interval_ms,
    :max_batch_size,
    :queue,
    :push_counter,
    :flush_counter
  ]
end
```

### 5.2 Pristine Adapter Improvements

#### 5.2.1 Enhanced Retry Port

```elixir
# pristine/lib/pristine/ports/retry.ex
defmodule Pristine.Ports.Retry do
  @callback with_retry((-> term()), keyword()) :: term()

  # New callbacks
  @callback should_retry?(term()) :: boolean()
  @callback extract_retry_after(map()) :: non_neg_integer() | nil
end
```

#### 5.2.2 Add Semaphore Port

```elixir
# pristine/lib/pristine/ports/semaphore.ex (new file)
defmodule Pristine.Ports.Semaphore do
  @moduledoc """
  Semaphore boundary for connection limiting.
  """

  @callback acquire(term(), timeout()) :: :ok | {:error, :timeout}
  @callback release(term()) :: :ok
  @callback with_permit(term(), timeout(), (-> result)) :: result | {:error, :timeout}
        when result: term()
end
```

#### 5.2.3 Enhanced Telemetry Port

```elixir
# pristine/lib/pristine/ports/telemetry.ex
defmodule Pristine.Ports.Telemetry do
  @callback emit(atom(), map(), map()) :: :ok

  # New callbacks
  @callback measure(atom(), map(), (-> result)) :: result when result: term()
  @callback emit_counter(atom(), map()) :: :ok
  @callback emit_gauge(atom(), number(), map()) :: :ok
  @callback start_span(atom(), map()) :: reference()
  @callback end_span(reference(), map()) :: :ok
end
```

#### 5.2.4 Add Foundation Telemetry Adapter

```elixir
# pristine/lib/pristine/adapters/telemetry/foundation.ex (new file)
defmodule Pristine.Adapters.Telemetry.Foundation do
  @behaviour Pristine.Ports.Telemetry

  alias Foundation.Telemetry

  @impl true
  def emit(event, meta, meas) do
    Telemetry.execute([event], meas, meta)
  end

  @impl true
  def measure(event, meta, fun) do
    Telemetry.measure([event], meta, fun)
  end

  @impl true
  def emit_counter(event, meta) do
    Telemetry.emit_counter([event], meta)
  end

  @impl true
  def emit_gauge(event, value, meta) do
    Telemetry.emit_gauge([event], value, meta)
  end
end
```

---

## 6. Concrete Next Steps (TDD Approach)

### Phase 1: Retry-After Header Support (Priority: High)

**Test First**:
```elixir
# test/foundation/retry/http_test.exs
defmodule Foundation.Retry.HTTPTest do
  use ExUnit.Case

  alias Foundation.Retry.HTTP

  describe "parse_retry_after/1" do
    test "parses retry-after-ms header" do
      assert HTTP.parse_retry_after(%{"retry-after-ms" => "500"}) == 500
    end

    test "parses retry-after seconds header" do
      assert HTTP.parse_retry_after(%{"retry-after" => "5"}) == 5000
    end

    test "parses retry-after HTTP date header" do
      # 10 seconds in the future
      future = DateTime.utc_now() |> DateTime.add(10, :second) |> http_date()
      result = HTTP.parse_retry_after(%{"retry-after" => future})
      assert_in_delta result, 10_000, 1000
    end

    test "returns nil for missing header" do
      assert HTTP.parse_retry_after(%{}) == nil
    end
  end
end
```

**Implementation**:
1. Create `Foundation.Retry.HTTP` module
2. Wire into `Foundation.Retry.Policy` via `retry_after_ms_fun`
3. Update `Pristine.Adapters.Retry.Foundation` to pass HTTP response

### Phase 2: Semaphore/Connection Limiting (Priority: High)

**Test First**:
```elixir
# test/pristine/adapters/semaphore/counting_test.exs
defmodule Pristine.Adapters.Semaphore.CountingTest do
  use ExUnit.Case

  alias Pristine.Adapters.Semaphore.Counting

  describe "with_permit/3" do
    test "limits concurrent executions" do
      sem = Counting.new(:test_sem, 2)
      results = for _ <- 1..5 do
        Task.async(fn ->
          Counting.with_permit(sem, 1000, fn ->
            Process.sleep(100)
            :ok
          end)
        end)
      end
      assert Enum.all?(Task.await_many(results), &(&1 == :ok))
    end

    test "returns timeout error when full" do
      sem = Counting.new(:test_sem_timeout, 1)
      Task.async(fn ->
        Counting.with_permit(sem, :infinity, fn ->
          Process.sleep(1000)
        end)
      end)
      Process.sleep(50)
      assert {:error, :timeout} = Counting.with_permit(sem, 0, fn -> :ok end)
    end
  end
end
```

**Implementation**:
1. Create `Pristine.Ports.Semaphore` behaviour
2. Create `Pristine.Adapters.Semaphore.Counting` using `Foundation.Semaphore.Counting`
3. Wire into `Pristine.Core.Pipeline` for request throttling

### Phase 3: Enhanced Telemetry (Priority: Medium)

**Test First**:
```elixir
# test/pristine/adapters/telemetry/foundation_test.exs
defmodule Pristine.Adapters.Telemetry.FoundationTest do
  use ExUnit.Case

  alias Pristine.Adapters.Telemetry.Foundation, as: TelemetryAdapter

  describe "measure/3" do
    test "times function execution and emits event" do
      :telemetry.attach("test", [:pristine, :test], &handler/4, self())

      result = TelemetryAdapter.measure(:test, %{key: "value"}, fn ->
        Process.sleep(10)
        :result
      end)

      assert result == :result
      assert_receive {:telemetry, [:pristine, :test], %{duration: d}, %{key: "value"}}
      assert d >= 10_000_000  # at least 10ms in native time
    end
  end
end
```

**Implementation**:
1. Extend `Pristine.Ports.Telemetry` with new callbacks
2. Create `Pristine.Adapters.Telemetry.Foundation`
3. Update existing adapters to implement new callbacks (noop for Reporter)

### Phase 4: Session-Scoped Telemetry Reporter (Priority: Medium)

**Test First**:
```elixir
# test/foundation/telemetry/session_reporter_test.exs
defmodule Foundation.Telemetry.SessionReporterTest do
  use ExUnit.Case

  alias Foundation.Telemetry.SessionReporter

  describe "batching" do
    test "batches events and flushes at threshold" do
      {:ok, reporter} = SessionReporter.start_link(
        session_id: "test-123",
        flush_threshold: 5,
        backend_fn: fn batch -> send(self(), {:batch, batch}) end
      )

      for i <- 1..5 do
        SessionReporter.log(reporter, "event.#{i}", %{i: i})
      end

      assert_receive {:batch, events}
      assert length(events) == 5
    end
  end
end
```

**Implementation**:
1. Port core logic from `Tinkex.Telemetry.Reporter`
2. Extract Tinker-specific types into generic structs
3. Add pluggable backend function instead of hardcoded HTTP client

### Phase 5: Pipeline Integration (Priority: Low)

**Test First**:
```elixir
# test/pristine/core/pipeline_test.exs
defmodule Pristine.Core.PipelineTest do
  use ExUnit.Case

  describe "execute/2 with full resilience stack" do
    test "applies rate limiting, circuit breaker, and retry" do
      request = %Request{method: :get, url: "http://test/api"}
      context = %Context{
        rate_limit_key: :test_api,
        circuit_breaker_name: "test-endpoint",
        retry_policy: %{max_attempts: 3}
      }

      # Mock transport to fail twice then succeed
      # Verify circuit breaker stays closed
      # Verify rate limiter is consulted
      # Verify retry happens
    end
  end
end
```

**Implementation**:
1. Create `Pristine.Core.Pipeline.execute/2` that orchestrates all adapters
2. Wire up telemetry at each stage
3. Add Retry-After extraction from HTTP responses

---

## 7. File Reference Summary

### Tinker Python SDK (Source)
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` - Core client with retry logic
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_constants.py` - Default values
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/retry_handler.py` - Retry orchestration
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/telemetry.py` - Session telemetry
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/telemetry_provider.py` - Provider protocol

### Pristine Elixir (Target)
- `/home/home/p/g/n/pristine/lib/pristine/ports/transport.ex` - Transport port
- `/home/home/p/g/n/pristine/lib/pristine/ports/retry.ex` - Retry port
- `/home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex` - Telemetry port
- `/home/home/p/g/n/pristine/lib/pristine/ports/circuit_breaker.ex` - Circuit breaker port
- `/home/home/p/g/n/pristine/lib/pristine/ports/rate_limit.ex` - Rate limit port
- `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex` - Finch transport
- `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex` - Foundation retry adapter
- `/home/home/p/g/n/pristine/lib/pristine/adapters/circuit_breaker/foundation.ex` - Foundation CB adapter
- `/home/home/p/g/n/pristine/lib/pristine/adapters/rate_limit/backoff_window.ex` - Backoff window adapter
- `/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/reporter.ex` - Telemetry reporter adapter

### Foundation Library
- `/home/home/p/g/n/foundation/lib/foundation/retry.ex` - Retry orchestration
- `/home/home/p/g/n/foundation/lib/foundation/backoff.ex` - Backoff strategies
- `/home/home/p/g/n/foundation/lib/foundation/circuit_breaker.ex` - Circuit breaker state machine
- `/home/home/p/g/n/foundation/lib/foundation/circuit_breaker/registry.ex` - CB registry
- `/home/home/p/g/n/foundation/lib/foundation/rate_limit/backoff_window.ex` - Backoff windows
- `/home/home/p/g/n/foundation/lib/foundation/telemetry.ex` - Telemetry API
- `/home/home/p/g/n/foundation/lib/foundation/graceful_degradation.ex` - Fallback mechanisms

### Tinkex Elixir (Reference)
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry.ex` - Retry with Foundation
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_config.ex` - User-facing config
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry.ex` - Console logging
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter.ex` - Backend reporting
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker.ex` - CB wrapper
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker/registry.ex` - CB registry
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/rate_limiter.ex` - Rate limiting
