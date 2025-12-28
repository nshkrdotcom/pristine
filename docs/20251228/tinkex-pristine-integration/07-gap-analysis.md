# Gap Analysis: Tinker Python SDK vs Pristine

## Executive Summary

This document provides a comprehensive gap analysis comparing the capabilities of the Tinker Python SDK against Pristine's current implementation. The goal is to identify specific enhancements needed for Pristine to generate a production-quality Tinkex client with minimal hand-written code.

**Overall Assessment**: Pristine has strong architectural foundations but requires significant enhancements in type system, code generation, and runtime capabilities to achieve feature parity with Tinker.

---

## 1. Type System Gaps

### 1.1 Discriminated Unions (CODE GENERATION GAP)

**Tinker Has**:
```python
ModelInputChunk: TypeAlias = Annotated[
    Union[EncodedTextChunk, ImageAssetPointerChunk, ImageChunk],
    PropertyInfo(discriminator="type")
]
```

**Sinter Has** (already implemented at `sinter/lib/sinter/types.ex:320-368`):
```elixir
{:discriminated_union, [
  discriminator: :type,
  variants: %{
    "encoded_text" => EncodedTextChunk.schema(),
    "image" => ImageChunk.schema()
  }
]}
```

**Gap**: Pristine's code generation doesn't yet use Sinter's discriminated union support.

**Gap Severity**: HIGH - Code generation enhancement, NOT type system limitation

**Required Enhancement**:
- Add `discriminator` field to type definitions in manifest
- Update `Pristine.Codegen.Type` to generate `{:discriminated_union, opts}`
- Generate pattern-matching decode functions using Sinter's union validation

### 1.2 Literal Types (CODE GENERATION GAP)

**Tinker Has**:
```python
type: Literal["encoded_text"] = "encoded_text"
Severity: TypeAlias = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
```

**Sinter Has** (already supported):
```elixir
{:literal, "encoded_text"}          # Single literal value
{:choices, ["DEBUG", "INFO", ...]}  # Enum of allowed values
```

**Gap**: Pristine's code generation uses `choices` but not `{:literal, value}`.

**Gap Severity**: MEDIUM - Code generation enhancement

**Required Enhancement**:
- Add `literal` type to manifest schema
- Generate `{:literal, value}` for single-value literals
- Continue using `{:choices, [...]}` for enum literals

### 1.3 Nested Type References

**Tinker Has**:
```python
class SampleResponse(BaseModel):
    sequences: Sequence[SampledSequence]  # References another type
```

**Pristine Has**:
- Basic type mapping (string, integer, etc.)
- No automatic nested type resolution

**Gap Severity**: HIGH - Affects complex response parsing

**Required Enhancement**:
- Implement type reference resolution in manifest
- Generate nested schema definitions
- Support recursive type references

### 1.4 Custom Validators/Serializers

**Tinker Has**:
```python
@field_validator("data", mode="before")
def validate_data(cls, value):
    if isinstance(value, str):
        return base64.b64decode(value)
    return value

@field_serializer("data")
def serialize_data(self, value: bytes) -> str:
    return base64.b64encode(value).decode("utf-8")
```

**Pristine Has**:
- No custom validator hooks
- No custom serializer hooks

**Gap Severity**: MEDIUM - Affects binary data handling, date parsing

**Required Enhancement**:
- Add `validator` and `serializer` hooks to manifest field definitions
- Generate validator/serializer code in type modules

### 1.5 NotGiven Sentinel

**Tinker Has**:
```python
class NotGiven:
    """Distinguishes omitted kwargs from None values"""
```

**Pristine Has**:
- Sinter has `NotGiven` concept
- Not fully integrated into generated code

**Gap Severity**: MEDIUM - Affects optional parameter handling

**Required Enhancement**:
- Ensure generated code properly uses `Sinter.NotGiven`
- Strip NotGiven values from request payloads

---

## 2. Manifest Schema Gaps

### 2.1 Missing Endpoint Fields

| Field | Tinker Uses | Pristine Has | Gap |
|-------|-------------|--------------|-----|
| `timeout` | Per-endpoint timeouts | Global only | MEDIUM |
| `async` | Boolean for async endpoints | Missing | HIGH |
| `poll_endpoint` | Link to polling endpoint | Missing | HIGH |
| `stream_format` | SSE, WebSocket, NDJSON | `streaming: true` only | MEDIUM |
| `deprecated` | Deprecation status | Missing | LOW |
| `tags` | Endpoint categorization | Missing | LOW |
| `error_types` | Endpoint-specific errors | Missing | MEDIUM |
| `response_unwrap` | Response extraction path | Missing | MEDIUM |

### 2.2 Missing Manifest-Level Fields

| Field | Purpose | Gap Severity |
|-------|---------|--------------|
| `base_url` | API base URL | HIGH |
| `auth` | Global auth configuration | MEDIUM |
| `error_types` | Common error definitions | HIGH |
| `resources` | Explicit resource groupings | LOW |
| `servers` | Multiple environment URLs | LOW |
| `retry_policies` | Named retry strategies | MEDIUM |
| `rate_limits` | Named rate limit configs | MEDIUM |

### 2.3 Type Definition Extensions

**Required New Fields**:
```json
{
  "types": {
    "ModelInputChunk": {
      "type": "union",
      "discriminator": "type",
      "variants": [
        {"type_ref": "EncodedTextChunk", "discriminator_value": "encoded_text"},
        {"type_ref": "ImageChunk", "discriminator_value": "image"}
      ]
    }
  }
}
```

---

## 3. Code Generation Gaps

### 3.1 Function Variants

**Tinker Generates**:
- `create_sample()` - Sync request
- `create_sample_async()` - Returns future
- `create_sample_stream()` - Returns stream

**Pristine Generates**:
- Single function per endpoint

**Gap Severity**: HIGH

**Required Enhancement**:
- Generate streaming variants for `streaming: true` endpoints
- Generate async variants for `async: true` endpoints
- Generate separate functions with appropriate suffixes

### 3.2 Typed Parameters

**Tinker Has**:
```python
async def create(
    self,
    *,
    session_id: str,
    model_seq_id: int,
    base_model: str,
    user_metadata: Optional[dict[str, Any]] = None,
    lora_config: Optional[LoraConfig] = None,
    idempotency_key: str | None = None,
) -> UntypedAPIFuture:
```

**Pristine Generates**:
```elixir
def create(resource, payload, opts \\ [])
```

**Gap Severity**: HIGH - Poor developer experience

**Required Enhancement**:
- Extract parameters from request type
- Generate typed function signatures
- Add path parameters to signature

### 3.3 Documentation Generation

**Tinker Has**:
- Parameter descriptions
- Return type documentation
- Example usage
- Deprecation warnings

**Pristine Has**:
- Basic @doc with description

**Gap Severity**: MEDIUM

**Required Enhancement**:
- Generate parameter documentation
- Generate return type documentation
- Add example code blocks

### 3.4 Response Wrappers

**Tinker Has**:
```python
@cached_property
def with_raw_response(self) -> AsyncModelsWithRawResponse:
    return AsyncModelsWithRawResponse(self)

@cached_property
def with_streaming_response(self) -> AsyncModelsWithStreamingResponse:
    return AsyncModelsWithStreamingResponse(self)
```

**Pristine Has**:
- None

**Gap Severity**: MEDIUM

**Required Enhancement**:
- Generate `with_raw_response` variant functions
- Generate `with_streaming_response` variant functions

---

## 4. Runtime Pipeline Gaps

### 4.1 Error Handling

**Tinker Has**:
```python
Exception Hierarchy:
├── TinkerError
    ├── APIStatusError
    │   ├── BadRequestError (400)
    │   ├── AuthenticationError (401)
    │   ├── RateLimitError (429)
    │   └── InternalServerError (5xx)
    └── APIConnectionError
```

**Pristine Has** (already implemented at `lib/pristine/error.ex:196-204`):
```elixir
# Pristine.Error struct with status-to-type mapping:
defp status_to_type(400), do: :bad_request
defp status_to_type(401), do: :authentication
defp status_to_type(429), do: :rate_limit
defp status_to_type(status) when status >= 500, do: :internal_server
# ... plus retriable? detection and x-should-retry header support
```

**Gap Severity**: LOW - Optional enhancement

**Optional Enhancement**:
- Add typed exception modules for exception-based pattern matching
- Current struct-based approach is already production-ready

### 4.2 Response Unwrapping

**Tinker Has**:
- Automatic extraction of nested response data
- Response caching by type

**Pristine Has**:
- Returns raw decoded JSON

**Gap Severity**: MEDIUM

**Required Enhancement**:
- Add `response_unwrap` path to manifest
- Implement nested data extraction
- Cache parsed responses

### 4.3 Retry Logic

**Tinker Has**:
- Per-endpoint timeout override
- Exponential backoff with jitter
- Retry-After header parsing
- Idempotency key reuse across retries
- Status code based retry decisions (408, 429, 5xx)

**Pristine Has** (already implemented):
- Per-endpoint retry via manifest `retry` field
- Exponential backoff with jitter via Foundation.Retry
- Idempotency key generation (lib/pristine/core/pipeline.ex:326-332)
- Status code based retriable detection (lib/pristine/error.ex:173-186)

**Gap Severity**: LOW

**Remaining Enhancement**:
- Add Retry-After header parsing
- Per-endpoint timeout configuration (manifest field exists, needs wiring)

### 4.4 Streaming

**Tinker Has**:
- SSE decoder with stateful parsing
- Multi-line data field accumulation
- Last-Event-ID persistence
- Typed event deserialization
- Stream cancellation

**Pristine Has**:
- Basic SSEDecoder
- No event type dispatch
- No Last-Event-ID handling

**Gap Severity**: HIGH

**Required Enhancement**:
- Add event type routing based on discriminator
- Implement Last-Event-ID persistence
- Add stream cancellation
- Support reconnection

### 4.5 Future/Polling

**Tinker Has**:
- Automatic polling with backoff
- Queue state observation
- Timeout enforcement
- Combined futures with transformation
- Result caching
- Telemetry integration

**Pristine Has**:
- Basic polling loop in `execute_future/5`
- No queue state handling
- No combined futures

**Gap Severity**: HIGH

**Required Enhancement**:
- Add queue state callbacks
- Implement combined futures
- Add proper timeout handling
- Integrate telemetry

---

## 5. Utility Gaps

### 5.1 Query String Serialization

**Tinker Has**:
- Array formats: comma, repeat, brackets, indices
- Nested formats: dots, brackets
- Configurable per-client

**Pristine Has**:
- Basic query string encoding
- No format options

**Gap Severity**: MEDIUM

**Required Enhancement**:
- Add query string format configuration to context
- Implement multiple serialization strategies

### 5.2 File Upload

**Tinker Has**:
- PathLike -> (filename, bytes) conversion
- Async file reading
- Base64 encoding option
- Multipart form data

**Pristine Has**:
- Basic multipart support
- No async file reading

**Gap Severity**: MEDIUM

**Required Enhancement**:
- Integrate with multipart_ex
- Add async file handling
- Support base64 encoding

### 5.3 Telemetry Headers

**Tinker Has**:
```python
{
    "X-Stainless-Package-Version": version,
    "X-Stainless-OS": platform,
    "X-Stainless-Arch": architecture,
    "X-Stainless-Runtime": runtime,
    "X-Stainless-Runtime-Version": version,
    "x-stainless-retry-count": retries_taken,
}
```

**Pristine Has**:
- Basic telemetry events
- No platform headers

**Gap Severity**: LOW

**Required Enhancement**:
- Add platform detection
- Inject telemetry headers
- Track retry count

---

## 6. Gap Priority Matrix

> **Note**: Many items previously listed as gaps are already implemented.
> This matrix reflects the actual remaining work.

### High (Blocks Full Functionality)
1. Discriminated union code generation (Sinter support exists)
2. Async endpoint variants in code generation
3. Streaming function generation
4. Nested type reference resolution in codegen

### Medium (Feature Enhancements)
1. Literal type code generation (Sinter support exists)
2. Typed function parameters in codegen
3. Future polling enhancements
4. Base URL and auth in manifest
5. Response unwrapping

### Low (Polish Items)
1. Custom validators/serializers
2. Per-endpoint timeout wiring
3. Query string format options
4. Retry-After header parsing
5. Deprecation markers
6. Endpoint tags
7. Platform telemetry headers

### Already Implemented ✓
1. ~~Error type hierarchy~~ - Status mapping exists (lib/pristine/error.ex)
2. ~~Idempotency key generation~~ - Automatic (lib/pristine/core/pipeline.ex)
3. ~~Per-endpoint retry~~ - Via manifest retry field
4. ~~Retriable detection~~ - x-should-retry + status codes

---

## 7. Estimated Impact

### With Current Pristine (No Enhancements)
- Custom code needed: ~800 lines
- Generated code utility: ~60%
- Development time: HIGH

### With Critical + High Enhancements
- Custom code needed: ~200 lines
- Generated code utility: ~90%
- Development time: MEDIUM

### With All Enhancements
- Custom code needed: ~100 lines
- Generated code utility: ~95%
- Development time: LOW

---

*Document created: 2025-12-28*
*Source: Synthesis of exploration agent findings*
