# Pristine Extensions Required

This document specifies what needs to be added to Pristine to support Tinkex (and future SDKs).

## Dependency Inventory

Pristine leverages these local dependencies that provide significant infrastructure:

### Foundation (path: "../foundation")
**Provides:** Retry, backoff, circuit breaker, rate limiting, semaphores, dispatch limiting

- `Foundation.Backoff` - Backoff policies (exponential, linear, constant, jitter)
- `Foundation.Retry` - Retry loops with policies, handlers, and HTTP helpers
- `Foundation.Retry.HTTP` - HTTP-specific retry determination and Retry-After parsing
- `Foundation.CircuitBreaker` - Circuit breakers with registry support
- `Foundation.CircuitBreaker.Registry` - Named circuit breaker management
- `Foundation.RateLimit.BackoffWindow` - Shared backoff windows for rate-limited APIs
- `Foundation.Semaphore.Counting` - Counting semaphores for concurrency limits
- `Foundation.Semaphore.Weighted` - Weighted semaphores for byte/token budgets
- `Foundation.Dispatch` - Layered dispatch limiter (concurrency + bytes under backoff)
- `Foundation.Poller` - Polling helper for long-running workflows
- `Foundation.Telemetry` - Telemetry helpers with reporter integration

### Sinter (path: "../sinter")
**Provides:** Schema definition, validation, JSON Schema generation, transforms

- `Sinter.Schema` - Runtime and compile-time schema definitions
- `Sinter.Validator` - Validation with coercion support
- `Sinter.JsonSchema` - JSON Schema generation (Draft 2020-12 and Draft 7)
- `Sinter.Transform` - Data transformation utilities
- `Sinter.NotGiven` - Sentinel for "not provided" vs nil
- `Sinter.JSON` - JSON encode/decode with aliasing and omit handling

### Multipart.Ex (path: "../multipart_ex")
**Provides:** Multipart/form-data encoding

- `Multipart.encode/2` - Form-data encoding with file support

### TelemetryReporter (path: "../telemetry_reporter")
**Provides:** Batched telemetry transport with backpressure

- `TelemetryReporter` - Batched event transport with size/time flushing
- `TelemetryReporter.Transport` - Transport behaviour for custom backends
- `TelemetryReporter.TelemetryAdapter` - Forward :telemetry events to reporter

---

## Current Pristine Inventory

### Ports (12 existing)
- `Transport` - HTTP send
- `StreamTransport` - SSE streaming
- `Serializer` - JSON encode/decode
- `Multipart` - Form encoding
- `Auth` - Header generation
- `Retry` - Retry orchestration
- `RateLimit` - Rate limiting
- `CircuitBreaker` - Circuit breaking
- `Semaphore` - Concurrency limiting
- `Future` - Async polling
- `Telemetry` - Observability
- `Tokenizer` - Token counting

### Adapters (19 existing)
- Transport: Finch, FinchStream
- Serializer: JSON
- Multipart: Ex (uses multipart_ex)
- Auth: Bearer, ApiKey, ApiKeyAlias
- Retry: Foundation (uses Foundation.Retry), Noop
- RateLimit: BackoffWindow, Noop
- CircuitBreaker: Foundation (uses Foundation.CircuitBreaker.Registry), Noop
- Semaphore: Counting
- Future: Polling
- Telemetry: Foundation, Reporter (uses TelemetryReporter), Noop
- Tokenizer: Tiktoken

---

## Required Extensions

### Priority 1: Core Infrastructure

These are essential for Tinkex to work and are NOT provided by dependencies:

#### 1.1 Compression Support

**What**: Request/response body compression (gzip)

**Why Needed**: Tinkex uses gzip compression for large payloads. None of the dependencies provide this.

**New Files**:
```
lib/pristine/ports/compression.ex
lib/pristine/adapters/compression/gzip.ex
lib/pristine/adapters/compression/noop.ex
```

**Port Interface**:
```elixir
defmodule Pristine.Ports.Compression do
  @callback compress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback decompress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback content_encoding() :: String.t()
end
```

**Implementation Notes**:
- Use Erlang's `:zlib` module for gzip
- Integrate into pipeline for automatic request compression and response decompression

---

#### 1.2 Bytes Semaphore Adapter

**What**: Byte-budget based concurrency limiting

**Why Needed**: Foundation provides `Semaphore.Weighted` but Pristine needs an adapter that conforms to `Pristine.Ports.Semaphore`.

**New Files**:
```
lib/pristine/adapters/semaphore/bytes.ex
```

**Implementation**:
```elixir
defmodule Pristine.Adapters.Semaphore.Bytes do
  @behaviour Pristine.Ports.Semaphore

  @doc """
  Adapter wrapping Foundation.Semaphore.Weighted for byte-budget limiting.
  """

  @impl true
  def with_acquire(name, cost, fun, opts \\ []) do
    # Delegate to Foundation.Semaphore.Weighted
  end
end
```

---

#### 1.3 Session Management

**What**: Persistent session with heartbeats for long-running connections

**Why Needed**: Not provided by any dependency. Tinkex training sessions need session tracking.

**New Files**:
```
lib/pristine/core/session.ex
lib/pristine/core/session_manager.ex
```

**Interface**:
```elixir
defmodule Pristine.Core.Session do
  defstruct [:id, :created_at, :last_heartbeat, :metadata]

  def new(id, opts \\ [])
  def expired?(session, ttl_ms)
end

defmodule Pristine.Core.SessionManager do
  use GenServer

  def start_link(opts)
  def ensure_session(manager, create_fn, opts)
  def session_id(manager)
  def heartbeat(manager)
end
```

---

#### 1.4 Enhanced Error Types

**What**: Richer error categorization with retry hints

**Why Needed**: Foundation provides retry logic but not HTTP-specific error classification structures.

**Modify**: `lib/pristine/error.ex`

```elixir
defmodule Pristine.Error do
  defstruct [
    :message,
    :type,           # :api_connection, :api_timeout, :api_status, :validation
    :status,         # HTTP status if applicable
    :category,       # :user (non-retryable), :server (retryable)
    :retry_after_ms, # Hint from server
    :request_id,     # For debugging
    :data            # Additional context
  ]

  # Factory functions
  def connection_error(reason, opts \\ [])
  def timeout_error(opts \\ [])
  def status_error(status, body, opts \\ [])
  def validation_error(message, opts \\ [])

  # Classification (integrates with Foundation.Retry.HTTP)
  def retryable?(%__MODULE__{category: :server}), do: true
  def retryable?(_), do: false
end
```

---

#### 1.5 Environment/Config Utilities

**What**: Centralized environment variable handling

**Why Needed**: Common SDK pattern not provided by dependencies.

**New Files**:
```
lib/pristine/core/env.ex
```

```elixir
defmodule Pristine.Core.Env do
  @doc "Get env var with fallback"
  def get(key, default \\ nil)

  @doc "Get required env var, raise if missing"
  def fetch!(key)

  @doc "Get env var as integer"
  def get_integer(key, default \\ nil)

  @doc "Get env var as boolean"
  def get_boolean(key, default \\ false)

  @doc "Check if running in test environment"
  def test?()
end
```

---

### Priority 2: Telemetry Enhancements

#### 2.1 Telemetry Capture Macro

**What**: Convenient capture/emit pattern

**Why Needed**: Syntactic sugar not provided by Foundation.Telemetry or TelemetryReporter.

**New Files**:
```
lib/pristine/core/telemetry/capture.ex
```

```elixir
defmodule Pristine.Core.Telemetry.Capture do
  @doc """
  Capture telemetry event with automatic timing.
  """
  defmacro async_capture(event, metadata, do: block)
  defmacro capture(event, metadata, do: block)
end
```

---

#### 2.2 OpenTelemetry Integration

**What**: OTEL context propagation

**Why Needed**: Not provided by TelemetryReporter which focuses on batched transport.

**New Files**:
```
lib/pristine/adapters/telemetry/otel.ex
```

```elixir
defmodule Pristine.Adapters.Telemetry.Otel do
  @behaviour Pristine.Ports.Telemetry

  @doc "Inject OTEL trace headers into request"
  def inject_headers(headers)

  @doc "Extract OTEL context from response"
  def extract_context(headers)
end
```

---

### Priority 3: File Handling

#### 3.1 File Reader

**What**: Async file reading with transforms

**Why Needed**: SDK-specific file handling not provided by dependencies.

**New Files**:
```
lib/pristine/core/files/reader.ex
lib/pristine/core/files/async_reader.ex
```

```elixir
defmodule Pristine.Core.Files.Reader do
  def read(path, opts \\ [])
  def read_json(path)
  def stream_lines(path)
end

defmodule Pristine.Core.Files.AsyncReader do
  def read_async(path, opts \\ [])
  def read_many(paths, opts \\ [])
end
```

---

### Priority 4: Future Enhancements

#### 4.1 Future Combiner

**What**: Combine multiple futures

**Why Needed**: Not provided by Foundation.Poller which handles single polling workflows.

**New Files**:
```
lib/pristine/adapters/future/combiner.ex
```

```elixir
defmodule Pristine.Adapters.Future.Combiner do
  def all(futures, opts \\ [])
  def race(futures, opts \\ [])
  def map(items, fun, opts \\ [])
end
```

---

### Priority 5: Utilities

#### 5.1 Logging Utilities

**What**: Structured logging with level control

**Why Needed**: SDK-specific logging patterns beyond standard Logger.

**New Files**:
```
lib/pristine/core/logging.ex
```

```elixir
defmodule Pristine.Core.Logging do
  def log(level, message, metadata \\ [])
  def debug(message, metadata \\ [])
  def info(message, metadata \\ [])
  def warn(message, metadata \\ [])
  def error(message, metadata \\ [])
  def level_enabled?(level)
end
```

---

## Removed from Scope (Provided by Dependencies)

The following items from the original document are **already covered** by dependencies:

| Original Item | Provided By | Notes |
|---------------|-------------|-------|
| Retry orchestration | Foundation.Retry | Already integrated via `Pristine.Adapters.Retry.Foundation` |
| Circuit breaker | Foundation.CircuitBreaker | Already integrated via `Pristine.Adapters.CircuitBreaker.Foundation` |
| Rate limiting | Foundation.RateLimit.BackoffWindow | Already integrated |
| Counting semaphore | Foundation.Semaphore.Counting | Already integrated via `Pristine.Adapters.Semaphore.Counting` |
| Telemetry batching/transport | TelemetryReporter | Already integrated via `Pristine.Adapters.Telemetry.Reporter` |
| Schema validation | Sinter.Validator | Use directly in generated code |
| JSON Schema generation | Sinter.JsonSchema | Use directly in codegen |
| NotGiven sentinel | Sinter.NotGiven | Use directly |
| Transform utilities | Sinter.Transform | Use directly |
| Multipart encoding | Multipart.encode/2 | Already integrated via `Pristine.Adapters.Multipart.Ex` |
| HTTP retry helpers | Foundation.Retry.HTTP | Already integrated in Retry adapter |
| Poller for long-running | Foundation.Poller | Use directly or wrap in Future adapter |

---

## Dependency Integration Guide

### Using Sinter for Schema Validation

Instead of manual schema definitions, use Sinter in generated code:

```elixir
# In generated type modules
defmodule Tinkex.Types.AdamParams do
  @schema Sinter.Schema.define([
    {:beta1, :float, [required: true, gt: 0.0, lt: 1.0]},
    {:beta2, :float, [required: true, gt: 0.0, lt: 1.0]},
    {:epsilon, :float, [required: true, gt: 0.0]},
    {:learning_rate, :float, [required: true, gt: 0.0]}
  ])

  def validate(data), do: Sinter.Validator.validate(@schema, data, coerce: true)
  def json_schema(), do: Sinter.JsonSchema.generate(@schema)
end
```

### Using Foundation for Resilience

Already integrated. Configuration example:

```elixir
# In client configuration
config = %Pristine.Core.Context{
  retry: Pristine.Adapters.Retry.Foundation,
  retry_policies: %{
    default: Foundation.Retry.Policy.new(
      max_attempts: 3,
      backoff: Foundation.Backoff.Policy.new(
        strategy: :exponential,
        base_ms: 1000,
        max_ms: 60_000
      ),
      retry_on: &match?({:error, _}, &1)
    )
  },
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation
}
```

### Using TelemetryReporter for Batched Events

Already integrated. Start the reporter in your application:

```elixir
# In your application.ex
children = [
  {TelemetryReporter,
    name: TelemetryReporter,
    transport: MyApp.TelemetryTransport,
    max_batch_size: 100,
    max_batch_delay: :timer.seconds(5)
  }
]

# The Pristine.Adapters.Telemetry.Reporter adapter will use it
```

### Using Multipart.Ex

Already integrated via `Pristine.Adapters.Multipart.Ex`. Use the port:

```elixir
Pristine.Ports.Multipart.encode(context.multipart, payload)
```

---

## Summary: New Modules Required

| Priority | Category | New Modules | Est. LOC |
|----------|----------|-------------|----------|
| P1 | Compression | 3 | 150 |
| P1 | Semaphore (Bytes) | 1 | 50 |
| P1 | Session | 2 | 200 |
| P1 | Error | 0 (modify) | 50 |
| P1 | Env | 1 | 80 |
| P2 | Telemetry Capture | 1 | 80 |
| P2 | OTEL | 1 | 100 |
| P3 | Files | 2 | 150 |
| P4 | Future Combiner | 1 | 100 |
| P5 | Logging | 1 | 80 |
| **Total** | | **13** | **~1,040** |

**Reduction from original**: 21 modules -> 13 modules (~38% reduction)

---

## Context Enhancement

The `Pristine.Core.Context` struct needs these additional fields:

```elixir
defstruct [
  # Existing
  :base_url, :headers, :auth,
  :transport, :stream_transport, :serializer, :multipart,
  :retry, :rate_limiter, :circuit_breaker, :semaphore,
  :telemetry, :future, :tokenizer,
  :retry_policies, :type_schemas, :transport_opts,
  # New
  :compression,          # Compression adapter
  :session_manager,      # Session manager pid
  :env,                  # Environment config
  :logger,               # Logger config
]
```

---

## Pipeline Enhancement

The `Pristine.Core.Pipeline` needs:

1. **Compression integration** - Compress request bodies, decompress responses
2. **Session header injection** - Add session ID to requests
3. **OTEL propagation** - Inject/extract trace context
4. **Enhanced error mapping** - Richer error classification using Pristine.Error
