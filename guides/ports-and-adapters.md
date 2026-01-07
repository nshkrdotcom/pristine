# Ports and Adapters Reference

Pristine implements a hexagonal architecture where **ports** define interface contracts and **adapters** provide concrete implementations. This guide documents all available ports and their adapters.

## Port Overview

| Port | Purpose | Adapters |
|------|---------|----------|
| Transport | HTTP request/response | Finch |
| StreamTransport | Streaming responses | FinchStream |
| Serializer | Payload encoding | JSON |
| Auth | Authentication | Bearer, APIKey |
| Retry | Retry logic | Foundation, Noop |
| CircuitBreaker | Failure isolation | Foundation, Noop |
| RateLimit | Request throttling | BackoffWindow, Noop |
| Telemetry | Observability | Foundation, Raw, Reporter, Noop |
| Compression | Payload compression | Gzip |
| Multipart | Form encoding | Ex |
| Tokenizer | LLM tokens | Tiktoken |
| Semaphore | Concurrency control | Counting |
| BytesSemaphore | Byte-budget limiting | GenServer |
| Future | Async polling | Polling |
| PoolManager | Connection pools | Default |

## Transport Ports

### Transport (`Pristine.Ports.Transport`)

Standard HTTP request/response transport.

```elixir
@callback send(Request.t(), Context.t()) ::
  {:ok, Response.t()} | {:error, term()}
```

#### Finch Adapter

```elixir
Pristine.Adapters.Transport.Finch
```

**Configuration:**
```elixir
context = %Context{
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [
    finch: MyApp.Finch,      # Finch instance name
    pool_name: :default,      # Connection pool
    timeout: 30_000,          # Request timeout (ms)
    receive_timeout: 60_000   # Receive timeout (ms)
  ]
}
```

### StreamTransport (`Pristine.Ports.StreamTransport`)

Streaming HTTP responses for SSE and chunked transfers.

```elixir
@callback stream(Request.t(), Context.t()) ::
  {:ok, StreamResponse.t()} | {:error, term()}
```

#### FinchStream Adapter

```elixir
Pristine.Adapters.Transport.FinchStream
```

**Configuration:**
```elixir
context = %Context{
  stream_transport: Pristine.Adapters.Transport.FinchStream,
  transport_opts: [
    finch: MyApp.Finch,
    receive_timeout: 60_000
  ]
}
```

**Usage:**
```elixir
{:ok, response} = Pipeline.execute_stream(manifest, :stream_endpoint, payload, context)

response.stream
|> Stream.each(fn event ->
  IO.inspect(event)
end)
|> Stream.run()
```

## Serializer Port

### Serializer (`Pristine.Ports.Serializer`)

Encodes request payloads and decodes response bodies.

```elixir
@callback encode(term(), keyword()) :: {:ok, binary()} | {:error, term()}
@callback decode(binary(), schema :: term(), keyword()) :: {:ok, term()} | {:error, term()}
```

#### JSON Adapter

```elixir
Pristine.Adapters.Serializer.JSON
```

**Features:**
- Uses Jason for JSON encoding/decoding
- Integrates with Sinter for schema validation
- Supports type coercion

**Configuration:**
```elixir
context = %Context{
  serializer: Pristine.Adapters.Serializer.JSON
}

# With validation options
opts = [
  path: "response.data",  # Error path context
  coerce: true            # Enable type coercion
]
```

## Authentication Ports

### Auth (`Pristine.Ports.Auth`)

Generates authentication headers.

```elixir
@callback headers(keyword()) :: {:ok, map()} | {:error, term()}
```

#### Bearer Adapter

```elixir
Pristine.Adapters.Auth.Bearer
```

**Usage:**
```elixir
context = %Context{
  auth: [
    {Pristine.Adapters.Auth.Bearer, token: "your-token"}
  ]
}
# Produces: Authorization: Bearer your-token
```

#### APIKey Adapter

```elixir
Pristine.Adapters.Auth.APIKey
```

**Usage:**
```elixir
context = %Context{
  auth: [
    {Pristine.Adapters.Auth.APIKey,
      value: "your-api-key",
      header: "X-API-Key"  # Default header name
    }
  ]
}
```

**Multiple Auth:**
```elixir
context = %Context{
  auth: [
    {Pristine.Adapters.Auth.Bearer, token: "token"},
    {Pristine.Adapters.Auth.APIKey, value: "key", header: "X-Custom-Key"}
  ]
}
```

## Resilience Ports

### Retry (`Pristine.Ports.Retry`)

Implements retry logic for failed operations.

```elixir
@callback with_retry((-> term()), keyword()) :: term()
@callback should_retry?(map()) :: boolean()  # Optional
@callback build_policy(keyword()) :: term()  # Optional
@callback parse_retry_after(map()) :: non_neg_integer() | nil  # Optional
```

#### Foundation Adapter

```elixir
Pristine.Adapters.Retry.Foundation
```

**Configuration:**
```elixir
context = %Context{
  retry: Pristine.Adapters.Retry.Foundation,
  retry_policies: %{
    "default" => %{
      max_attempts: 3,
      backoff: :exponential,
      base_delay_ms: 1000,
      max_delay_ms: 30_000
    }
  }
}
```

**Features:**
- HTTP-aware retry decisions (retries 429, 5xx)
- Parses Retry-After headers
- Exponential, linear, and custom backoff
- Jitter support

#### Noop Adapter

```elixir
Pristine.Adapters.Retry.Noop
```

Executes once without retries. Useful for testing.

### CircuitBreaker (`Pristine.Ports.CircuitBreaker`)

Prevents cascading failures by opening circuits on repeated failures.

```elixir
@callback call(key :: String.t(), (-> term()), keyword()) :: term()
```

#### Foundation Adapter

```elixir
Pristine.Adapters.CircuitBreaker.Foundation
```

**Configuration:**
```elixir
context = %Context{
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation
}
```

**Per-endpoint circuit breakers:**
Circuits are keyed by endpoint ID, providing isolation between endpoints.

#### Noop Adapter

```elixir
Pristine.Adapters.CircuitBreaker.Noop
```

Always executes without circuit breaking.

### RateLimit (`Pristine.Ports.RateLimit`)

Enforces rate limits and implements backpressure.

```elixir
@callback within_limit((-> term()), keyword()) :: term()
@callback wait(term(), keyword()) :: :ok  # Optional
@callback set(term(), window_ms, keyword()) :: :ok  # Optional
```

#### BackoffWindow Adapter

```elixir
Pristine.Adapters.RateLimit.BackoffWindow
```

**Configuration:**
```elixir
context = %Context{
  rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow
}
```

**Features:**
- Sliding window rate limiting
- Server-driven backoff (from 429 responses)
- Per-key rate limits

#### Noop Adapter

```elixir
Pristine.Adapters.RateLimit.Noop
```

No rate limiting applied.

## Observability Ports

### Telemetry (`Pristine.Ports.Telemetry`)

Emits telemetry events for monitoring and debugging.

```elixir
@callback emit(event, metadata, measurements) :: :ok
@callback measure(event, metadata, (-> term())) :: term()  # Optional
@callback emit_counter(event, metadata) :: :ok  # Optional
@callback emit_gauge(event, value, metadata) :: :ok  # Optional
```

#### Foundation Adapter

```elixir
Pristine.Adapters.Telemetry.Foundation
```

**Events emitted:**
- `[:pristine, :request, :start]`
- `[:pristine, :request, :stop]`
- `[:pristine, :request, :exception]`
- `[:pristine, :stream, :start]`
- `[:pristine, :stream, :connected]`
- `[:pristine, :stream, :error]`

**Attaching handlers:**
```elixir
:telemetry.attach(
  "my-handler",
  [:pristine, :request, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("Request completed in #{measurements.duration}ms")
  end,
  nil
)
```

#### Raw Adapter

```elixir
Pristine.Adapters.Telemetry.Raw
```

Direct `:telemetry` emission without event prefixing.

#### Reporter Adapter

```elixir
Pristine.Adapters.Telemetry.Reporter
```

Integrates with `telemetry_reporter` for batched event reporting.

#### Noop Adapter

```elixir
Pristine.Adapters.Telemetry.Noop
```

Discards all telemetry. Useful for testing.

## Compression Port

### Compression (`Pristine.Ports.Compression`)

Compresses and decompresses payloads.

```elixir
@callback compress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
@callback decompress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
@callback content_encoding() :: String.t()
```

#### Gzip Adapter

```elixir
Pristine.Adapters.Compression.Gzip
```

**Usage:**
```elixir
# Automatic decompression of gzip responses
# Set Content-Encoding: gzip header
```

## Multipart Port

### Multipart (`Pristine.Ports.Multipart`)

Encodes multipart/form-data for file uploads.

```elixir
@callback encode(term(), keyword()) :: {content_type :: binary(), body :: iodata()}
```

#### Ex Adapter

```elixir
Pristine.Adapters.Multipart.Ex
```

**Usage:**
```elixir
# In manifest
{
  "id": "upload_file",
  "body_type": "multipart"
}

# Payload
%{
  "file" => %{filename: "doc.pdf", content: binary},
  "description" => "My document"
}
```

## Tokenizer Port

### Tokenizer (`Pristine.Ports.Tokenizer`)

Encodes/decodes text to LLM tokens.

```elixir
@callback encode(String.t(), keyword()) :: {:ok, [integer()]} | {:error, term()}
@callback decode([integer()], keyword()) :: {:ok, String.t()} | {:error, term()}
```

#### Tiktoken Adapter

```elixir
Pristine.Adapters.Tokenizer.Tiktoken
```

**Usage:**
```elixir
{:ok, tokens} = Pristine.Adapters.Tokenizer.Tiktoken.encode(
  "Hello, world!",
  encoding: "cl100k_base"
)
```

## Semaphore Ports

### Semaphore (`Pristine.Ports.Semaphore`)

Limits concurrent operations.

```elixir
@callback with_permit(name, timeout, (-> term())) :: term() | {:error, :timeout}
@callback init(name, limit) :: :ok  # Optional
```

#### Counting Adapter

```elixir
Pristine.Adapters.Semaphore.Counting
```

**Usage:**
```elixir
Pristine.Adapters.Semaphore.Counting.init(:my_semaphore, 10)

Pristine.Adapters.Semaphore.Counting.with_permit(:my_semaphore, 5000, fn ->
  # Limited to 10 concurrent executions
  make_request()
end)
```

### BytesSemaphore (`Pristine.Ports.BytesSemaphore`)

Byte-budget rate limiting for memory/bandwidth control.

```elixir
@callback acquire(server, bytes, timeout) :: :ok | {:error, :timeout}
@callback release(server, bytes) :: :ok
@callback available(server) :: non_neg_integer()
```

#### GenServer Adapter

```elixir
Pristine.Adapters.BytesSemaphore.GenServer
```

**Usage:**
```elixir
{:ok, sem} = Pristine.Adapters.BytesSemaphore.GenServer.start_link(
  max_bytes: 5_242_880  # 5MB
)

# Acquire bytes before request
:ok = Pristine.Adapters.BytesSemaphore.GenServer.acquire(sem, 1024, 5000)

# Release after response
:ok = Pristine.Adapters.BytesSemaphore.GenServer.release(sem, 1024)
```

## Future Port

### Future (`Pristine.Ports.Future`)

Polls for async operation results.

```elixir
@callback poll(request_id, Context.t(), opts) :: {:ok, Task.t()} | {:error, term()}
@callback await(Task.t(), timeout) :: {:ok, term()} | {:error, term()}
```

#### Polling Adapter

```elixir
Pristine.Adapters.Future.Polling
```

**Usage:**
```elixir
# Execute async endpoint
{:ok, response} = Pipeline.execute_future(manifest, :async_endpoint, payload, context,
  poll_interval_ms: 1000,
  max_poll_time_ms: 300_000,
  backoff: :exponential
)

# Response contains Task
{:ok, result} = Task.await(response.task, 300_000)
```

## Creating Custom Adapters

Implement any port behavior:

```elixir
defmodule MyApp.CustomTransport do
  @behaviour Pristine.Ports.Transport

  @impl true
  def send(%Pristine.Core.Request{} = request, %Pristine.Core.Context{} = context) do
    # Your implementation
    {:ok, %Pristine.Core.Response{
      status: 200,
      headers: %{},
      body: "response",
      metadata: %{}
    }}
  end
end

# Use your adapter
context = %Context{
  transport: MyApp.CustomTransport
}
```

## Adapter Selection Guide

### For Production

```elixir
%Context{
  transport: Pristine.Adapters.Transport.Finch,
  stream_transport: Pristine.Adapters.Transport.FinchStream,
  serializer: Pristine.Adapters.Serializer.JSON,
  retry: Pristine.Adapters.Retry.Foundation,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
  rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow,
  telemetry: Pristine.Adapters.Telemetry.Foundation
}
```

### For Testing

```elixir
%Context{
  transport: MockTransport,
  serializer: Pristine.Adapters.Serializer.JSON,
  retry: Pristine.Adapters.Retry.Noop,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
  rate_limiter: Pristine.Adapters.RateLimit.Noop,
  telemetry: Pristine.Adapters.Telemetry.Noop
}
```
