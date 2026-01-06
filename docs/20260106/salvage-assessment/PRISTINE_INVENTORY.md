# Pristine Module Inventory

**Date**: 2026-01-06
**Purpose**: Detailed catalog of what pristine provides and its quality

---

## Summary

| Category | Files | Lines | Quality | Keep? |
|----------|-------|-------|---------|-------|
| Core Pipeline | 10 | 860 | Excellent | YES |
| Manifest | 4 | 640 | Good | YES |
| Ports | 12 | 150 | Good | YES |
| Adapters | 20+ | 1,543 | Good | YES |
| Code Generation | 4 | 1,663 | Excellent | YES |
| Streaming | 2 | 311 | Excellent | YES |
| Error Handling | 1 | 227 | Good | YES |
| Runtime | 1 | 45 | Good | YES |
| Testing | 2 | 85 | Fair | YES |
| Mix Tasks | 4 | 150+ | Good | YES |
| **Total** | **60+** | **4,686** | **Good** | **YES** |

---

## Core Pipeline (`lib/pristine/core/`)

### `pipeline.ex` (562 lines) - EXCELLENT

The heart of pristine. Orchestrates request execution through resilience stack.

**Key functions:**
- `execute/5` - Synchronous request execution
- `execute_stream/5` - SSE streaming with lazy enumerable
- `execute_future/5` - Long-running operations with polling

**Architecture:**
```elixir
# Resilience stack composition
defp execute_with_resilience(context, request, endpoint) do
  with_retry(context, fn ->
    with_rate_limit(context, fn ->
      with_circuit_breaker(context, fn ->
        transport_execute(context, request)
      end)
    end)
  end)
end
```

### `context.ex` (85 lines) - GOOD

Runtime execution context holding all adapter implementations.

```elixir
defstruct [
  transport: nil,
  serializer: nil,
  retry: Pristine.Adapters.Retry.Noop,
  rate_limiter: Pristine.Adapters.RateLimit.Noop,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
  auth: nil,
  telemetry: Pristine.Adapters.Telemetry.Noop,
  tokenizer: nil,
  multipart: nil,
  future: nil,
  stream_transport: nil,
  semaphore: nil,
  config: %{}
]
```

### Other Core Modules

| Module | Lines | Purpose |
|--------|-------|---------|
| `request.ex` | 22 | Normalized request struct |
| `response.ex` | 18 | Normalized response struct |
| `stream_response.ex` | 109 | SSE wrapper with enumerable |
| `auth.ex` | 18 | Auth header application |
| `headers.ex` | 25 | Header building |
| `url.ex` | 30 | URL construction |
| `querystring.ex` | 35 | Query string encoding |
| `telemetry_headers.ex` | 20 | Telemetry header injection |

---

## Manifest System (`lib/pristine/manifest/`)

### `manifest.ex` (507 lines) - GOOD

Comprehensive manifest loading, validation, normalization.

**Validates:**
- Required fields (name, version, endpoints, types)
- Endpoint structure (method, path, request/response types)
- Type definitions (objects, unions, aliases)
- Retry policies, rate limits, auth strategies

### `endpoint.ex` (66 lines)

Endpoint definition struct with 33 configurable fields:
```elixir
defstruct [
  :name, :method, :path, :resource,
  :request_type, :response_type,
  :streaming, :async, :idempotent,
  :auth, :timeout, :retry,
  :rate_limit, :circuit_breaker,
  # ... 19 more fields
]
```

### `loader.ex` (~35 lines)

File loading with YAML/JSON auto-detection.

### `schema.ex` (~30 lines)

Sinter-based manifest schema validation.

---

## Ports (`lib/pristine/ports/`)

All use `@behaviour` for compile-time contract checking.

| Port | Lines | Contract |
|------|-------|----------|
| `transport.ex` | 12 | `request(Request.t()) :: {:ok, Response.t()} \| {:error, term()}` |
| `serializer.ex` | 15 | `encode/decode` with optional schema validation |
| `retry.ex` | 18 | `with_retry/2`, `should_retry?/1`, `parse_retry_after/1` |
| `rate_limit.ex` | 10 | `within_limit/2` for concurrency control |
| `circuit_breaker.ex` | 12 | `call/3` for fault tolerance |
| `auth.ex` | 8 | `headers/1` for auth injection |
| `telemetry.ex` | 10 | `emit/3` for observability |
| `tokenizer.ex` | 12 | Token counting for LLM integration |
| `multipart.ex` | 10 | Form-data encoding |
| `future.ex` | 15 | Long-running operation polling |
| `stream_transport.ex` | 12 | Streaming response handling |
| `semaphore.ex` | 10 | Counting semaphore |

---

## Adapters (`lib/pristine/adapters/`)

### Transport

| Adapter | Lines | Description |
|---------|-------|-------------|
| `finch.ex` | ~80 | HTTP via Finch library |
| `finch_stream.ex` | 273 | SSE streaming with Task-based dispatch |

### Serializer

| Adapter | Lines | Description |
|---------|-------|-------------|
| `json.ex` | ~60 | JSON via Jason + Sinter validation |

### Retry

| Adapter | Lines | Description |
|---------|-------|-------------|
| `foundation.ex` | 157 | Foundation library with Retry-After |
| `noop.ex` | 15 | Pass-through |

### Auth

| Adapter | Lines | Description |
|---------|-------|-------------|
| `api_key.ex` | 25 | Static API key header |
| `api_key_alias.ex` | 25 | Alternative header name |
| `bearer.ex` | 25 | Bearer token |

### CircuitBreaker

| Adapter | Lines | Description |
|---------|-------|-------------|
| `foundation.ex` | ~50 | Foundation library |
| `noop.ex` | 15 | Pass-through |

### RateLimit

| Adapter | Lines | Description |
|---------|-------|-------------|
| `backoff_window.ex` | ~80 | Time-window based |
| `noop.ex` | 15 | Pass-through |

### Telemetry

| Adapter | Lines | Description |
|---------|-------|-------------|
| `foundation.ex` | ~50 | Foundation library |
| `reporter.ex` | ~80 | Batching via telemetry_reporter |
| `noop.ex` | 15 | Pass-through |

### Other

| Adapter | Lines | Description |
|---------|-------|-------------|
| `multipart/ex.ex` | ~40 | multipart_ex integration |
| `tokenizer/tiktoken.ex` | ~35 | tiktoken_ex integration |
| `semaphore/counting.ex` | ~50 | Simple counting semaphore |

---

## Code Generation (`lib/pristine/codegen/`)

### `codegen.ex` (~100 lines)

Orchestrator for code generation pipeline.

```elixir
def build_sources(manifest, opts) do
  types = build_type_modules(manifest)
  resources = build_resource_modules(manifest)
  client = build_client_module(manifest, resources)

  {:ok, %{types: types, resources: resources, client: client}}
end
```

### `type.ex` (789 lines) - EXCELLENT

Generates type modules with full validation:

```elixir
# Generated output example:
defmodule MySDK.Types.User do
  use Sinter.Schema

  schema do
    field :id, :string, required: true
    field :email, :string, required: true
    field :role, :enum, values: [:admin, :user]
  end

  def decode(data), do: Sinter.decode(__MODULE__, data)
  def encode(struct), do: Sinter.encode(struct)
end
```

### `resource.ex` (623 lines) - EXCELLENT

Generates resource modules with typed functions:

```elixir
# Generated output example:
defmodule MySDK.Resources.Users do
  def get(%{context: ctx}, user_id, opts \\ []) do
    Pristine.Runtime.execute(ctx, :get_user, %{user_id: user_id}, opts)
  end

  def create(%{context: ctx}, params, opts \\ []) do
    Pristine.Runtime.execute(ctx, :create_user, params, opts)
  end
end
```

### `elixir.ex` (251 lines) - GOOD

Generates main client module:

```elixir
# Generated output example:
defmodule MySDK.Client do
  defstruct [:context]

  def new(opts) do
    context = build_context(opts)
    %__MODULE__{context: context}
  end

  def users(client), do: MySDK.Resources.Users.with_client(client)
end
```

---

## Streaming (`lib/pristine/streaming/`)

### `event.ex` (112 lines) - EXCELLENT

SSE Event struct with parsing:

```elixir
defstruct [:id, :event, :data, :retry]

def json(%__MODULE__{data: data}) do
  case Jason.decode(data) do
    {:ok, parsed} -> {:ok, parsed}
    {:error, _} -> {:error, :invalid_json}
  end
end
```

### `sse_decoder.ex` (200 lines) - EXCELLENT

RFC-compliant SSE parser:

```elixir
def decode_stream(chunks) do
  chunks
  |> Stream.transform(new(), fn chunk, state ->
    {events, new_state} = feed(state, chunk)
    {events, new_state}
  end)
end
```

Features:
- Stateful, incremental parsing
- All line endings (\\n\\n, \\r\\r, \\r\\n\\r\\n)
- Event ID tracking for reconnection
- Comment handling

---

## Error Handling (`lib/pristine/error.ex`, 227 lines)

Structured error types with semantic mapping:

```elixir
@error_types [:bad_request, :authentication, :permission_denied,
              :not_found, :conflict, :rate_limit, :internal_server,
              :timeout, :connection, :unknown]

def from_response(%{status: 400}), do: {:error, %__MODULE__{type: :bad_request, ...}}
def from_response(%{status: 401}), do: {:error, %__MODULE__{type: :authentication, ...}}
# ...

def retriable?(%__MODULE__{type: :rate_limit}), do: true
def retriable?(%__MODULE__{type: :internal_server}), do: true
def retriable?(_), do: false
```

---

## Mix Tasks (`lib/mix/tasks/`)

| Task | Description |
|------|-------------|
| `pristine.generate` | Generate SDK from manifest |
| `pristine.validate` | Validate manifest structure |
| `pristine.docs` | Generate markdown documentation |
| `pristine.openapi` | Generate OpenAPI spec |

---

## Test Suite (`test/`)

**Stats:**
- 354 tests, 0 failures
- 13,174 lines of test code
- Deterministic across seeds

**Coverage Areas:**
- Core pipeline (sync, stream, async)
- All adapters
- Code generation
- Manifest validation
- SSE parsing
- Error handling

---

## What's Missing

Needs to be added for tinkex support:

1. **BytesSemaphore** - Byte-budget rate limiting
2. **Compression** - Gzip/Zstd support
3. **Session** - Long-running connection management
4. **Environment** - Config from env vars

---

## Quality Assessment

| Aspect | Score | Notes |
|--------|-------|-------|
| Architecture | A | Proper hexagonal design |
| Code Quality | B+ | Some Agent usage could improve |
| Test Coverage | A | 354 passing tests |
| Documentation | B- | Module docs good, user docs sparse |
| Extensibility | A | Easy to add adapters |
| Performance | B | Not benchmarked, looks reasonable |

**Overall: Keep everything. Add missing ports for tinkex.**
