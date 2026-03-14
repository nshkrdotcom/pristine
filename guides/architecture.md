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

The same pipeline is also responsible for OpenAPI runtime wiring. If an endpoint carries direct refs such as `{MySDK.User, :t}`, the pipeline resolves those refs through generated `__schema__/1` helpers and can optionally materialize successful responses through `decode/1,2`.

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

Most production callers should not build that struct field-by-field. Use
`Pristine.foundation_context/1` to get cohesive default wiring over the
Foundation-backed adapters, then drop to `Pristine.context/1` only when you
need full manual control.

`type_schemas` now covers both manifest-compiled schemas and any direct OpenAPI refs resolved at runtime. That keeps the boundary generic: generated SDKs can opt into typed responses without copying runtime schema logic into each package.

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
- `TokenSource` - OAuth2 token lookup/storage
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

# Production - shared runtime profile
prod_context =
  Pristine.foundation_context(
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: MyApp.Finch],
    rate_limit: [key: {:my_app, :integration}, registry: MyApp.RateLimits],
    circuit_breaker: [registry: MyApp.Breakers],
    telemetry: [namespace: [:my_sdk]]
  )
```

## Data Flow

## Security And OAuth2 Boundaries

Pristine keeps the runtime transport boundary separate from OAuth2 control-plane helpers:

- normal endpoint execution still uses `Pristine.Core.Pipeline` and the configured transport adapter
- `Pristine.OAuth2` uses the optional `oauth2` dependency only for strategy shaping, authorization URL generation, and token parsing helpers
- `Pristine.OAuth2.CallbackServer` is a loopback-only helper that additionally requires the optional `plug` and `bandit` dependencies
- token, revoke, and introspection HTTP still execute through Pristine's transport boundary

Runtime auth can now be resolved from either legacy `auth` keys or OpenAPI-style `security` requirement sets. That lets generated SDKs opt into scheme-scoped auth such as bearer-vs-basic without introducing a client-wide "OAuth mode".

The same dependency boundary applies to the smaller compatibility adapters:

- `Pristine.Adapters.Telemetry.Reporter` remains available for `telemetry_reporter` compatibility, but it is no longer part of the default runtime dependency path
- `Pristine.Adapters.Tokenizer.Tiktoken` remains available for tokenization experiments, but it requires the optional `tiktoken_ex` dependency
- `foundation` stays in the core runtime package because the default production profile still depends on it directly

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
