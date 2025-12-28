# Pristine Enhancement Roadmap for Tinkex v2

## Overview

This roadmap outlines the specific enhancements required to make Pristine capable of generating a production-quality Tinkex v2 client with minimal hand-written code. Enhancements are organized by phase with clear dependencies and deliverables.

> **Important Corrections** (2025-12-28):
> - Sinter already supports discriminated unions (`{:discriminated_union, opts}`) and
>   literals (`{:literal, value}`). Phase 1 focuses on code generation integration.
> - Idempotency key generation already exists at `lib/pristine/core/pipeline.ex:326-332`
> - Status code mapping already exists at `lib/pristine/error.ex:196-204`

---

## Phase 1: Type System Code Generation (CRITICAL)

**Goal**: Integrate Sinter's existing type capabilities into Pristine's code generation

> **Note**: Sinter already provides discriminated unions at `sinter/lib/sinter/types.ex:320-368`
> and literal types. This phase focuses on code generation integration, not type system work.

### 1.1 Discriminated Union Code Generation

**Files to Modify**:
- `lib/pristine/manifest/type.ex` - Add discriminator field to struct
- `lib/pristine/codegen/type.ex` - Generate `{:discriminated_union, opts}` schemas
- `lib/pristine/manifest.ex` - Parse union definitions from JSON

**Manifest Schema Addition**:
```json
{
  "type": {
    "kind": "union",
    "discriminator": "type",
    "variants": [
      {
        "type_ref": "EncodedTextChunk",
        "discriminator_value": "encoded_text"
      },
      {
        "type_ref": "ImageChunk",
        "discriminator_value": "image"
      }
    ]
  }
}
```

**Generated Elixir**:
```elixir
def decode(data) when is_map(data) do
  case data["type"] do
    "encoded_text" -> EncodedTextChunk.decode(data)
    "image" -> ImageChunk.decode(data)
    _ -> {:error, :unknown_variant}
  end
end
```

**Deliverables**:
- [ ] Update Type struct with `kind`, `discriminator`, `variants`
- [ ] Implement union type code generation using `{:discriminated_union, opts}`
- [ ] Wire up to existing Sinter discriminated union validation
- [ ] Tests for union parsing and generation

### 1.2 Literal Type Code Generation

**Files to Modify**:
- `lib/pristine/manifest/field.ex` - Add literal field
- `lib/pristine/codegen/type.ex` - Generate `{:literal, value}` schemas

**Manifest Schema Addition**:
```json
{
  "fields": {
    "type": {
      "type": "literal",
      "value": "encoded_text"
    }
  }
}
```

**Deliverables**:
- [ ] Add `literal` type to field definitions
- [ ] Generate `{:literal, value}` or `{:choices, [...]}` as appropriate
- [ ] Support literal defaults in generated structs

### 1.3 Nested Type References

**Files to Modify**:
- `lib/pristine/codegen/type.ex` - Resolve type references
- `lib/pristine/manifest.ex` - Build type dependency graph

**Implementation**:
```elixir
defp resolve_type("SampledSequence", types) do
  Map.get(types, "SampledSequence")
end

defp generate_field_schema(field, types) when field.type_ref != nil do
  referenced_type = resolve_type(field.type_ref, types)
  "{:object, #{referenced_type.module}.schema()}"
end
```

**Deliverables**:
- [ ] Add `type_ref` field for type references
- [ ] Implement type resolution in code generation
- [ ] Handle circular references safely
- [ ] Generate proper Sinter nested object schemas

---

## Phase 2: Manifest Schema Enhancement

**Goal**: Capture all endpoint metadata needed for code generation

### 2.1 Async Endpoint Support

**Manifest Schema Addition**:
```json
{
  "endpoints": {
    "create_model": {
      "async": true,
      "poll_endpoint": "retrieve_future",
      "timeout": 300000
    }
  }
}
```

**Files to Modify**:
- `lib/pristine/manifest/endpoint.ex` - Add async, poll_endpoint, timeout
- `lib/pristine/codegen/resource.ex` - Generate async variants

**Deliverables**:
- [ ] Add `async`, `poll_endpoint`, `timeout` to Endpoint struct
- [ ] Parse async configuration from manifest
- [ ] Generate future-returning functions

### 2.2 Stream Configuration

**Manifest Schema Addition**:
```json
{
  "endpoints": {
    "create_sample_stream": {
      "streaming": true,
      "stream_format": "sse",
      "event_types": ["message_start", "content_block_delta", "message_stop"]
    }
  }
}
```

**Deliverables**:
- [ ] Add `stream_format`, `event_types` to Endpoint struct
- [ ] Generate streaming variant functions
- [ ] Add event type routing code

### 2.3 Base URL and Auth Configuration

**Manifest Schema Addition**:
```json
{
  "base_url": "https://api.tinker.ai/v1",
  "auth": {
    "type": "api_key",
    "header": "X-API-Key",
    "env_var": "TINKER_API_KEY"
  }
}
```

**Deliverables**:
- [ ] Add `base_url`, `auth` to Manifest struct
- [ ] Generate client initialization with auth
- [ ] Support environment variable fallbacks

### 2.4 Error Type Definitions

**Manifest Schema Addition**:
```json
{
  "error_types": {
    "400": "BadRequestError",
    "401": "AuthenticationError",
    "429": "RateLimitError",
    "5xx": "ServerError"
  }
}
```

**Deliverables**:
- [ ] Add `error_types` to Manifest struct
- [ ] Generate typed error modules
- [ ] Map status codes to error types in pipeline

---

## Phase 3: Code Generation Enhancement

**Goal**: Generate idiomatic, type-safe Elixir code

### 3.1 Typed Function Parameters

**Current**:
```elixir
def create(resource, payload, opts \\ [])
```

**Target**:
```elixir
@spec create(t(), String.t(), integer(), String.t(), keyword()) :: {:ok, Future.t()} | {:error, Error.t()}
def create(resource, session_id, model_seq_id, base_model, opts \\ [])
```

**Files to Modify**:
- `lib/pristine/codegen/resource.ex` - Extract parameters from request type
- Generate typespec from parameter types

**Deliverables**:
- [ ] Extract required fields from request type
- [ ] Generate typed function parameters
- [ ] Add path parameters to function signature
- [ ] Generate @spec annotations

### 3.2 Function Variants

**Files to Modify**:
- `lib/pristine/codegen/resource.ex` - Generate multiple functions per endpoint

**Generated Functions**:
```elixir
# Sync version
def create_sample(resource, payload, opts \\ [])

# Stream version
def create_sample_stream(resource, payload, opts \\ [])

# Async version (returns future)
def create_sample_async(resource, payload, opts \\ [])
```

**Deliverables**:
- [ ] Generate `_stream` variants for streaming endpoints
- [ ] Generate `_async` variants for async endpoints
- [ ] Generate raw response variants

### 3.3 Documentation Generation

**Files to Modify**:
- `lib/pristine/codegen/resource.ex` - Enhance @doc generation

**Generated Documentation**:
```elixir
@doc """
Creates a new model with optional LoRA fine-tuning configuration.

## Parameters

  * `session_id` - The session ID (required)
  * `model_seq_id` - Model sequence ID (required)
  * `base_model` - Base model name (required)
  * `opts` - Optional parameters
    * `:user_metadata` - Custom metadata
    * `:lora_config` - LoRA configuration
    * `:idempotency_key` - Idempotency key

## Returns

  * `{:ok, %Future{}}` on success
  * `{:error, %Error{}}` on failure

## Example

    {:ok, future} = Models.create(client.models, "session-123", 1, "Qwen/Qwen3-8B")
    {:ok, result} = Future.await(future)

"""
```

**Deliverables**:
- [ ] Extract parameter descriptions from manifest
- [ ] Generate parameter documentation
- [ ] Generate return type documentation
- [ ] Add example code blocks

---

## Phase 4: Runtime Pipeline Enhancement

**Goal**: Full-featured request/response handling

### 4.1 Error Type Hierarchy (ALREADY IMPLEMENTED)

> **Status**: Core functionality already exists at `lib/pristine/error.ex`
> - Status code to type mapping: lines 196-204
> - Retriable detection: lines 173-186
> - x-should-retry header support: lines 178-181

**Optional Enhancement** - Typed exception modules for exception-based matching:
```elixir
# Optional: If exception-based pattern matching is preferred
defmodule Pristine.Errors.BadRequestError do
  defexception [:message, :request, :body, status_code: 400]
end
```

**Remaining Deliverables**:
- [x] Status code -> error type mapping (EXISTS)
- [x] Retriable detection (EXISTS)
- [ ] Extract Retry-After header from response
- [ ] Optional: Typed exception modules

### 4.2 Response Unwrapping

**Files to Modify**:
- `lib/pristine/core/pipeline.ex` - Add unwrap step

**Manifest Addition**:
```json
{
  "response_unwrap": "data"
}
```

**Implementation**:
```elixir
defp unwrap_response(body, endpoint) do
  case endpoint.response_unwrap do
    nil -> body
    path -> get_in(body, String.split(path, "."))
  end
end
```

**Deliverables**:
- [ ] Add `response_unwrap` to endpoint
- [ ] Implement nested path extraction
- [ ] Handle missing paths gracefully

### 4.3 Enhanced Streaming

**Files to Modify**:
- `lib/pristine/runtime/stream_response.ex` - Event dispatch
- `lib/pristine/adapters/transport/sse_decoder.ex` - Last-Event-ID

**Implementation**:
```elixir
defmodule Pristine.Runtime.StreamResponse do
  def dispatch_event(event, handler) do
    case event.type do
      "message_start" -> handler.on_message_start(event.data)
      "content_block_delta" -> handler.on_content_block_delta(event.data)
      "message_stop" -> handler.on_message_stop(event.data)
      _ -> handler.on_unknown(event)
    end
  end
end
```

**Deliverables**:
- [ ] Implement event type routing
- [ ] Add Last-Event-ID tracking
- [ ] Support reconnection with Last-Event-ID
- [ ] Add stream cancellation

### 4.4 Enhanced Futures

**Files to Modify**:
- `lib/pristine/runtime/future.ex` - Full lifecycle management

**Implementation**:
```elixir
defmodule Pristine.Runtime.Future do
  defstruct [:request_id, :poll_fn, :cached_result, :status]

  def await(future, timeout \\ :infinity) do
    case future.cached_result do
      nil -> poll_until_complete(future, timeout)
      result -> {:ok, result}
    end
  end

  def combine(futures, transform_fn) do
    results = Task.async_stream(futures, &await/1) |> Enum.to_list()
    transform_fn.(results)
  end
end
```

**Deliverables**:
- [ ] Implement result caching
- [ ] Add timeout handling
- [ ] Implement combined futures
- [ ] Add queue state observation callbacks
- [ ] Integrate telemetry

---

## Phase 5: Utilities and Polish

**Goal**: Developer experience and edge cases

### 5.1 Query String Formatting

**Files to Modify**:
- `lib/pristine/core/context.ex` - Add format options

**Implementation**:
```elixir
defmodule Pristine.Utils.QueryString do
  def encode(params, opts \\ []) do
    array_format = Keyword.get(opts, :array_format, :repeat)
    nested_format = Keyword.get(opts, :nested_format, :brackets)
    # ... implementation
  end
end
```

**Deliverables**:
- [ ] Implement array format options (comma, repeat, brackets)
- [ ] Implement nested format options (dots, brackets)
- [ ] Make configurable per-client

### 5.2 Idempotency Key Generation (ALREADY IMPLEMENTED)

> **Status**: Already implemented at `lib/pristine/core/pipeline.ex:326-332`

**Existing Implementation**:
```elixir
# From lib/pristine/core/pipeline.ex:326-332
defp maybe_add_idempotency_header(headers, %{idempotency: true}, context, opts) do
  header_name = context.idempotency_header || "X-Idempotency-Key"
  key = Keyword.get(opts, :idempotency_key) || UUID.uuid4()
  Map.put(headers, header_name, key)
end

defp maybe_add_idempotency_header(headers, _endpoint, _context, _opts), do: headers
```

**Deliverables**:
- [x] Auto-generate idempotency keys when endpoint.idempotency: true (EXISTS)
- [x] Allow user override via opts[:idempotency_key] (EXISTS)
- [ ] Reuse key across retries (enhancement needed)

### 5.3 Platform Telemetry Headers

**Files to Modify**:
- `lib/pristine/core/pipeline.ex` - Add platform headers

**Implementation**:
```elixir
defp platform_headers do
  %{
    "X-Pristine-Version" => Pristine.version(),
    "X-Pristine-OS" => :os.type() |> elem(0) |> to_string(),
    "X-Pristine-Runtime" => "BEAM",
    "X-Pristine-Runtime-Version" => System.version()
  }
end
```

**Deliverables**:
- [ ] Detect platform information
- [ ] Inject telemetry headers
- [ ] Track retry count in headers

---

## Dependency Graph

```
Phase 1 (Type System Code Generation)
  ├── 1.1 Discriminated Union Codegen (uses existing Sinter support)
  ├── 1.2 Literal Type Codegen (uses existing Sinter support)
  └── 1.3 Nested Type References

Phase 2 (Manifest Schema) ─────────► depends on Phase 1
  ├── 2.1 Async Endpoint Support
  ├── 2.2 Stream Configuration
  ├── 2.3 Base URL and Auth
  └── 2.4 Error Type Definitions (optional, core exists)

Phase 3 (Code Generation) ─────────► depends on Phase 1 + 2
  ├── 3.1 Typed Function Parameters
  ├── 3.2 Function Variants
  └── 3.3 Documentation Generation

Phase 4 (Runtime Pipeline) ─────────► depends on Phase 2
  ├── 4.1 Error Type Hierarchy ────► ALREADY IMPLEMENTED (status mapping)
  ├── 4.2 Response Unwrapping
  ├── 4.3 Enhanced Streaming ──────► depends on 2.2
  └── 4.4 Enhanced Futures ────────► depends on 2.1

Phase 5 (Utilities) ───────────────► independent
  ├── 5.1 Query String Formatting
  ├── 5.2 Idempotency Keys ────────► ALREADY IMPLEMENTED
  └── 5.3 Platform Headers
```

---

## Validation Checkpoints

### After Phase 1
- [ ] Can parse Tinkex manifest with discriminated unions
- [ ] Generated types validate nested structures
- [ ] Union types resolve correctly

### After Phase 2
- [ ] Manifest includes all Tinkex endpoint metadata
- [ ] Auth configuration parsed correctly
- [ ] Error types defined in manifest

### After Phase 3
- [ ] Generated functions have typed parameters
- [ ] Streaming variants generated
- [ ] Documentation includes all parameters

### After Phase 4
- [x] Errors return typed structs (EXISTS: Pristine.Error with :type field)
- [ ] Streaming events dispatched by type
- [ ] Futures poll with caching

### After Phase 5
- [ ] Query strings formatted correctly
- [x] Idempotency keys auto-generated (EXISTS: lib/pristine/core/pipeline.ex:326)
- [ ] Platform headers injected

---

## Success Criteria

1. **Tinkex v2 Manifest**: Complete manifest representing all 25 Tinker endpoints
2. **Generated Client**: Full Tinkex client generated from manifest
3. **Test Coverage**: Integration tests pass against mock server
4. **Custom Code**: < 200 lines of hand-written code in Tinkex
5. **Parity**: Feature parity with Python SDK for supported operations

---

*Document created: 2025-12-28*
*Version: 1.0*
