# Architecture Overview

Pristine implements a hexagonal (ports and adapters) architecture that cleanly separates domain logic from infrastructure concerns. This design enables testability, flexibility, and maintainability.

## Core Principles

### 1. Separation of Concerns

```
┌─────────────────────────────────────────────────────────────┐
│                      User Code                              │
├─────────────────────────────────────────────────────────────┤
│                   Generated SDK Layer                       │
│         (Client, Resources, Types)                          │
├─────────────────────────────────────────────────────────────┤
│                    Pristine Core                            │
│    ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐     │
│    │ Pipeline│  │ Manifest │  │  Codegen │  │Streaming│     │
│    └────┬────┘  └────┬─────┘  └────┬─────┘  └────┬────┘     │
│         │            │             │              │         │
├─────────┴────────────┴─────────────┴──────────────┴─────────┤
│                         Ports                               │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌──────────────────┐ │
│  │Transport │ │Serializer│ │  Auth   │ │Retry/CB/RateLimit│ │
│  └────┬─────┘ └────┬─────┘ └────┬────┘ └────────┬─────────┘ │
├───────┴────────────┴────────────┴───────────────┴───────────┤
│                        Adapters                             │
│  ┌──────┐ ┌──────┐ ┌────────┐ ┌──────┐ ┌──────────────────┐ │
│  │Finch │ │ JSON │ │ Bearer │ │ Gzip │ │   Foundation     │ │
│  └──────┘ └──────┘ └────────┘ └──────┘ └──────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2. Manifest-Driven Design

The manifest serves as a single source of truth:

```
Manifest (JSON/YAML)
    │
    ├──► Code Generation ──► Type Modules
    │                    ──► Resource Modules
    │                    ──► Client Module
    │
    ├──► Runtime Execution ──► Request Pipeline
    │                      ──► Response Handling
    │
    └──► Documentation ──► API Docs
                       ──► OpenAPI Spec
```

### 3. Composable Resilience

Resilience patterns compose as nested function calls:

```
Rate Limiter
  └─► Circuit Breaker
       └─► Retry Logic
            └─► Transport
                 └─► HTTP Request
```

## Core Components

### Pipeline (`Pristine.Core.Pipeline`)

The pipeline orchestrates request execution through multiple stages:

```elixir
Pipeline.execute(manifest, endpoint_id, payload, context, opts)
```

**Stages:**
1. **Endpoint Lookup** - Fetch endpoint definition from manifest
2. **Request Encoding** - Serialize payload, build headers
3. **URL Construction** - Apply path/query parameters
4. **Resilience Stack** - Rate limit → Circuit breaker → Retry
5. **Transport** - Send HTTP request
6. **Response Processing** - Decompress, decode, validate

### Context (`Pristine.Core.Context`)

The context carries all runtime configuration:

```elixir
%Pristine.Core.Context{
  # Infrastructure
  base_url: "https://api.example.com",
  transport: Pristine.Adapters.Transport.Finch,
  serializer: Pristine.Adapters.Serializer.JSON,

  # Authentication
  auth: [{Pristine.Adapters.Auth.Bearer, token: "..."}],

  # Resilience
  retry: Pristine.Adapters.Retry.Foundation,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
  rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow,

  # Observability
  telemetry: Pristine.Adapters.Telemetry.Foundation,

  # Runtime state
  type_schemas: %{},
  retry_policies: %{}
}
```

### Request/Response (`Pristine.Core.Request`, `Pristine.Core.Response`)

Normalized data structures for transport abstraction:

```elixir
# Request - what goes to transport
%Pristine.Core.Request{
  method: "POST",
  url: "https://api.example.com/users",
  headers: %{"content-type" => "application/json"},
  body: "{\"name\":\"John\"}",
  endpoint_id: "create_user",
  metadata: %{}
}

# Response - what comes from transport
%Pristine.Core.Response{
  status: 200,
  headers: %{"content-type" => "application/json"},
  body: "{\"id\":\"123\",\"name\":\"John\"}",
  metadata: %{}
}
```

## Hexagonal Architecture

### Ports

Ports define interface contracts using Elixir behaviors:

```elixir
defmodule Pristine.Ports.Transport do
  @callback send(Request.t(), Context.t()) ::
    {:ok, Response.t()} | {:error, term()}
end
```

**Available Ports:**
- `Transport` - HTTP request/response
- `StreamTransport` - Streaming responses (SSE)
- `Serializer` - Encode/decode payloads
- `Auth` - Authentication headers
- `Retry` - Retry logic
- `CircuitBreaker` - Circuit breaker pattern
- `RateLimit` - Rate limiting
- `Telemetry` - Observability
- `Compression` - Payload compression
- `Multipart` - Form data encoding
- `Tokenizer` - LLM tokenization

### Adapters

Adapters implement port contracts:

```elixir
defmodule Pristine.Adapters.Transport.Finch do
  @behaviour Pristine.Ports.Transport

  @impl true
  def send(%Request{} = request, %Context{} = context) do
    # Implementation using Finch HTTP client
  end
end
```

**Swapping Adapters:**

```elixir
# Development - no resilience
dev_context = %Context{
  retry: Pristine.Adapters.Retry.Noop,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
  telemetry: Pristine.Adapters.Telemetry.Noop
}

# Production - full resilience
prod_context = %Context{
  retry: Pristine.Adapters.Retry.Foundation,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
  telemetry: Pristine.Adapters.Telemetry.Foundation
}
```

## Data Flow

### Standard Request

```
User Code
    │
    ▼
Pipeline.execute(manifest, :create_user, payload, context)
    │
    ├─► Lookup endpoint definition
    │
    ├─► Encode payload (serializer.encode)
    │
    ├─► Build request struct
    │   ├─► URL.build (base_url + path + params)
    │   ├─► Headers.build (base + endpoint + auth)
    │   └─► Auth.apply (authentication modules)
    │
    ├─► Execute with resilience stack
    │   ├─► rate_limiter.within_limit
    │   │   └─► circuit_breaker.call
    │   │       └─► retry.with_retry
    │   │           └─► transport.send
    │
    ├─► Process response
    │   ├─► Decompress (if gzip)
    │   ├─► Decode (serializer.decode)
    │   └─► Validate (against schema)
    │
    └─► Return {:ok, data} or {:error, reason}
```

### Streaming Request

```
User Code
    │
    ▼
Pipeline.execute_stream(manifest, :stream_endpoint, payload, context)
    │
    ├─► Build request (same as standard)
    │
    ├─► stream_transport.stream(request, context)
    │
    └─► Return {:ok, StreamResponse.t()}
            │
            ├─► .stream (Enumerable of events)
            ├─► .status (HTTP status)
            ├─► .headers (Response headers)
            └─► .metadata (cancel fn, last_event_id)
```

## Code Generation

The codegen pipeline transforms manifests to Elixir modules:

```
Manifest
    │
    ├─► Type.render_all_type_modules()
    │   └─► One module per type
    │       ├─► defstruct
    │       ├─► @type t
    │       ├─► schema() - Sinter validation
    │       ├─► decode/1, encode/1
    │       └─► from_map/1, to_map/1
    │
    ├─► Resource.render_all_resource_modules()
    │   └─► One module per resource group
    │       ├─► Endpoint functions
    │       ├─► Path parameter handling
    │       └─► Documentation
    │
    └─► Elixir.render_client_module()
        └─► Main client module
            ├─► new/1 constructor
            ├─► Resource accessors
            └─► Embedded manifest
```

## Testing Strategy

The hexagonal architecture enables easy testing:

```elixir
# Use Noop adapters in tests
test_context = %Context{
  transport: MockTransport,
  retry: Pristine.Adapters.Retry.Noop,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
  telemetry: Pristine.Adapters.Telemetry.Noop
}

# Mock only the transport
defmodule MockTransport do
  @behaviour Pristine.Ports.Transport

  def send(_request, _context) do
    {:ok, %Response{status: 200, body: "{\"success\":true}"}}
  end
end
```

## Extension Points

### Custom Adapters

Implement any port behavior:

```elixir
defmodule MyApp.CustomAuth do
  @behaviour Pristine.Ports.Auth

  @impl true
  def headers(opts) do
    token = generate_signature(opts)
    {:ok, %{"Authorization" => "Custom #{token}"}}
  end
end
```

### Custom Error Handling

Plug in custom error modules:

```elixir
context = %Context{
  error_module: MyApp.APIError
}

defmodule MyApp.APIError do
  def new(status, body, _headers) do
    %MyApp.APIError{
      status: status,
      message: body["error"]["message"],
      code: body["error"]["code"]
    }
  end
end
```

### Response Wrapping

Transform responses before returning:

```elixir
context = %Context{
  response_wrapper: MyApp.ResponseWrapper
}

defmodule MyApp.ResponseWrapper do
  def wrap(response, metadata) do
    %{
      data: response,
      request_id: metadata.request_id,
      latency_ms: metadata.elapsed_ms
    }
  end
end
```
