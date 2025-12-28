# Critical Self-Assessment: Pristine's Current State

## Executive Summary

This document provides an honest, critical evaluation of Pristine's current capabilities
versus what would be required to generate a production-quality Tinkex client. The goal is
to minimize hand-written code in Tinkex by maximizing Pristine's generation capabilities.

**Current State**: Pristine is a promising foundation but has significant gaps that would
require substantial hand-written code to work around.

---

## 1. Manifest Schema Limitations

### 1.1 Endpoint Definition Gaps

Current `Pristine.Manifest.Endpoint` struct:

```elixir
defstruct id: nil,
          method: nil,
          path: nil,
          description: nil,
          resource: nil,
          request: nil,
          response: nil,
          retry: nil,
          telemetry: nil,
          streaming: false,
          headers: %{},
          query: %{},
          body_type: nil,
          content_type: nil,
          auth: nil,
          circuit_breaker: nil,
          rate_limit: nil,
          idempotency: false
```

**Missing fields that Tinker SDK uses**:

| Field | Purpose | Why Needed |
|-------|---------|------------|
| `timeout` | Per-endpoint timeout override | Tinker has endpoint-specific timeouts |
| `async` | Boolean for async endpoints | Tinker uses futures extensively |
| `poll_endpoint` | Link to polling endpoint | For async result retrieval |
| `stream_format` | SSE, WebSocket, NDJSON | Tinker uses SSE |
| `deprecated` | Deprecation status | API evolution |
| `tags` | Endpoint categorization | Documentation grouping |
| `error_types` | Endpoint-specific errors | Error handling |
| `response_unwrap` | How to extract response data | Tinker has nested responses |

### 1.2 Type Definition Gaps

Current type handling is simplistic:

```elixir
defp map_type_to_sinter("string"), do: ":string"
defp map_type_to_sinter("integer"), do: ":integer"
# ... basic types only
```

**Missing type features**:

| Feature | Example in Tinker | Current Support |
|---------|-------------------|-----------------|
| Discriminated unions | `type: "text" \| "tool_use"` | ❌ None |
| Literal types | `type: Literal["pending"]` | ❌ None |
| Nested type refs | `content: List[ContentBlock]` | ⚠️ Partial |
| Optional with default | `max_tokens: int = 1024` | ⚠️ Partial |
| Union types | `str \| None` | ❌ None |
| Recursive types | Self-referencing types | ❌ None |
| Enum types | Fixed set of values | ⚠️ Via choices |
| Generic maps | `Dict[str, Any]` | ⚠️ Limited |

### 1.3 Manifest-Level Gaps

Current manifest only has:
- `name`, `version`
- `endpoints` (map)
- `types` (map)
- `policies` (map)

**Missing manifest features**:

- `base_url` - API base URL
- `auth` - Global auth configuration
- `error_types` - Common error definitions
- `resources` - Explicit resource groupings with metadata
- `servers` - Multiple environment URLs
- `retry_policies` - Named retry strategies
- `rate_limits` - Named rate limit configurations
- `middleware` - Request/response transformers

---

## 2. Code Generation Limitations

### 2.1 Resource Module Generation

Current generation (`Pristine.Codegen.Resource`):

```elixir
def #{fn_name}(%__MODULE__{context: context}, payload, opts \\ []) do
  Pristine.Runtime.execute(context, #{inspect(endpoint.id)}, payload, opts)
end
```

**Problems**:

1. **No streaming variants** - Should generate `fn_name_stream` for streaming endpoints
2. **No async variants** - Should generate `fn_name_async` for async endpoints
3. **No typed parameters** - All endpoints take `payload` map, not typed structs
4. **No path parameter extraction** - Path params not in function signature
5. **No documentation** - Function docs don't show parameters or return types
6. **No examples** - No usage examples in docs

### 2.2 Type Module Generation

Current generation (`Pristine.Codegen.Type`):

```elixir
def schema do
  Sinter.Schema.define([
    {:field_name, :type, [opts]}
  ])
end
```

**Problems**:

1. **No discriminated union support** - Critical for Tinker's event types
2. **No nested type validation** - Types reference other types by name, not schema
3. **No custom validators** - Can't add format validators (email, URI, etc.)
4. **No coercion** - No string-to-integer coercion for query params
5. **No serialization hooks** - Can't customize JSON encoding

### 2.3 Client Module Generation

Current generation creates basic client with resource accessors.

**Problems**:

1. **No default configuration** - Should read from env vars, config files
2. **No middleware hooks** - Can't add request/response interceptors
3. **No connection pooling config** - Finch pool not configurable
4. **No retry configuration** - Hard-coded or missing
5. **No telemetry hooks** - Not integrated with generated client

---

## 3. Runtime Pipeline Limitations

### 3.1 Request Building

Current `Pipeline.build_request/5` handles:
- URL construction with path params
- Header merging
- Body encoding
- Auth header injection
- Idempotency keys

**Missing**:

- Query parameter serialization (nested, arrays)
- File upload handling
- Request signing
- Request ID injection
- Custom header injection per endpoint

### 3.2 Response Handling

Current response flow:
1. Transport sends request
2. Response decoded by serializer
3. Data returned

**Missing**:

- Status code to error type mapping
- Response unwrapping (extract nested data)
- Pagination handling
- Response validation against schema
- Response transformation/normalization

### 3.3 Streaming

Current `Pipeline.execute_stream/5`:
- Creates StreamResponse
- Uses SSEDecoder

**Missing**:

- Event type dispatching
- Event accumulation
- Partial message assembly
- Stream cancellation
- Reconnection with last-event-id
- Heartbeat/ping handling

### 3.4 Futures/Polling

Current `Pipeline.execute_future/5`:
- Basic polling loop

**Missing**:

- Status-aware polling (only poll if "pending")
- Result extraction from poll response
- Polling backoff strategies
- Progress callbacks
- Timeout handling
- Cancellation

---

## 4. Comparison: Tinker SDK vs Pristine

### 4.1 What Tinker Does Well

| Feature | Tinker Implementation | Pristine Gap |
|---------|----------------------|--------------|
| Typed requests | Pydantic models with validation | Generic maps |
| Typed responses | Auto-parsed to typed objects | Returns raw maps |
| Streaming events | Strongly typed event classes | Untyped events |
| Futures | Full lifecycle management | Basic polling |
| File uploads | Multipart with progress | Basic multipart |
| Error handling | Typed exception hierarchy | Generic errors |
| Retry logic | Per-endpoint configuration | Global only |
| Rate limiting | Built-in with headers | External adapter |
| Idempotency | Automatic key generation | Manual |

### 4.2 Code Volume Comparison

If we port Tinker to Elixir without Pristine improvements:

| Component | Lines with Pristine (est.) | Lines without Pristine |
|-----------|---------------------------|------------------------|
| Types | 0 (generated) | 2000+ |
| Resources | 0 (generated) | 500+ |
| Client | 100 (config) | 800+ |
| Streaming | 300 (custom) | 300 |
| Futures | 200 (custom) | 200 |
| Errors | 200 (custom) | 200 |
| **Total** | 800 | 4000+ |

With Pristine enhancements:

| Component | Lines | Notes |
|-----------|-------|-------|
| Manifest | 500 (JSON) | Declarative |
| Config | 50 | Minimal |
| Custom code | 100 | Edge cases only |
| **Total** | 650 | 84% reduction |

---

## 5. Critical Path for Enhancement

### Priority 1: Type System (Blocks Everything)

1. Discriminated unions - Required for event types
2. Nested type references - Required for complex types
3. Literal types - Required for type discrimination
4. Optional/default handling - Required for request building

### Priority 2: Manifest Schema

1. Async endpoint support
2. Streaming configuration
3. Error type definitions
4. Base URL and auth configuration

### Priority 3: Code Generation

1. Streaming function variants
2. Async function variants
3. Typed parameters in signatures
4. Proper documentation generation

### Priority 4: Runtime

1. Status code to error mapping
2. Response unwrapping
3. Enhanced streaming with event dispatch
4. Proper future lifecycle

---

## 6. Honest Assessment

### What We Got Right

1. **Hexagonal architecture** - Port/adapter separation is solid
2. **Pipeline abstraction** - Composable request handling
3. **Manifest-driven approach** - Declarative is the right choice
4. **SSE decoder** - Well implemented
5. **Resource grouping** - SDK-style API

### What Needs Work

1. **Type system is too simple** - Can't represent Tinker's types
2. **Generated code is naive** - Missing streaming/async variants
3. **Runtime assumes happy path** - Error handling is weak
4. **Manifest schema is incomplete** - Missing critical fields
5. **No end-to-end validation** - Types aren't validated at runtime

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Type system rewrite | High | High | Start now |
| Manifest breaking changes | Medium | Medium | Version schema |
| Runtime complexity explosion | Medium | High | Keep it simple |
| Generated code bugs | High | Medium | More tests |

---

## 7. Recommendation

**Invest heavily in Pristine before building Tinkex v2.**

The current implementation would require ~800 lines of custom code in Tinkex.
With proper enhancements, this could be reduced to ~100 lines.

The type system enhancements alone would take 2-3 days but would pay dividends
across all future Pristine-generated clients.

---

*Document created: 2025-12-28*
*Author: Critical Self-Assessment Agent*
