# Pristine Architecture Audit: Gap Analysis

**Date**: 2025-12-28
**Status**: Comprehensive Gap Inventory Complete

---

## 1. Gap Inventory Summary

| Category | Critical Gaps | High Gaps | Medium Gaps | Low Gaps | Total |
|----------|---------------|-----------|-------------|----------|-------|
| Type System (Sinter) | 2 | 3 | 2 | 1 | 8 |
| Codegen | 1 | 3 | 4 | 2 | 10 |
| Serialization | 1 | 2 | 2 | 1 | 6 |
| Transport/Resilience | 0 | 3 | 3 | 2 | 8 |
| Streaming/Async | 6 | 0 | 0 | 0 | 6 |
| Multipart | 0 | 1 | 2 | 1 | 4 |
| CLI/Tooling | 1 | 4 | 4 | 2 | 11 |
| **Total** | **11** | **16** | **17** | **9** | **53** |

---

## 2. Critical Gaps (Must Fix for Tinker Compatibility)

### GAP-001: Discriminated Union Support in Sinter
**Severity**: CRITICAL | **Effort**: HIGH | **Blocks**: ModelInputChunk, FutureRetrieveResponse

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/model_input_chunk.py:11-13`):
```python
ModelInputChunk: TypeAlias = Annotated[
    Union[EncodedTextChunk, ImageAssetPointerChunk, ImageChunk],
    PropertyInfo(discriminator="type")
]
```

**Current Sinter**: Uses `{:union, [...]}` with sequential try-each validation.

**Required Change**:
```elixir
{:discriminated_union, [
  discriminator: "type",
  variants: %{
    "encoded_text" => EncodedTextChunk.schema(),
    "image" => ImageChunk.schema()
  }
]}
```

**Implementation Location**: `/home/home/p/g/n/sinter/lib/sinter/types.ex`

---

### GAP-002: SSE Decoder and Streaming Transport
**Severity**: CRITICAL | **Effort**: HIGH | **Blocks**: All streaming endpoints

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_streaming.py`):
- `SSEDecoder` class with chunk boundary detection
- `Stream[T]`/`AsyncStream[T]` typed iterators
- Context manager lifecycle

**Current Pristine**: No streaming support whatsoever.

**Required Changes**:
1. New `Pristine.Streaming.SSEDecoder` module
2. New `Pristine.Streaming.Event` struct
3. New `Pristine.Ports.StreamTransport` behaviour
4. New `Pristine.Core.StreamResponse` struct
5. New `Pristine.Adapters.Transport.FinchStream`
6. Pipeline `execute_stream/5` function

**Reference Implementation**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

---

### GAP-003: Future/Polling Abstraction
**Severity**: CRITICAL | **Effort**: HIGH | **Blocks**: All async operations

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/futures.py`):
- Simple `retrieve` endpoint that polls for async results
- Tinkex has sophisticated polling with backoff

**Tinkex Implementation** (`/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`):
- Task-based async polling
- Configurable poll timeouts
- Exponential backoff with Foundation.Backoff
- Queue state telemetry
- TryAgainResponse handling

**Required Changes**:
1. New `Pristine.Ports.Future` behaviour
2. New `Pristine.Adapters.Future.Polling` implementation
3. Pipeline integration for async operations

---

### GAP-004: Pre-validation Hooks in Sinter
**Severity**: CRITICAL | **Effort**: MEDIUM | **Blocks**: Complex type transforms

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/datum.py:31-44`):
```python
@model_validator(mode="before")
@classmethod
def convert_tensors(cls, data: Any) -> Any:
    # Transform data before validation
```

**Current Sinter**: Only `post_validate` function, no pre-validation.

**Required Change**:
```elixir
Schema.define([...], pre_validate: fn data ->
  # Transform data before validation
  update_in(data, ["field"], &transform/1)
end)
```

**Implementation Location**: `/home/home/p/g/n/sinter/lib/sinter/validator.ex`

---

### GAP-005: Per-field Validators
**Severity**: CRITICAL | **Effort**: MEDIUM | **Blocks**: Custom field validation

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py:27-38`):
```python
@field_validator("data", mode="before")
def validate_data(cls, value):
    if isinstance(value, str):
        return base64.b64decode(value)
    return value
```

**Current Sinter**: No per-field validation hooks.

**Required Change**:
```elixir
{:data, :string, [
  required: true,
  validate: fn value ->
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, "invalid base64"}
    end
  end
]}
```

---

### GAP-006: Per-field Serializers
**Severity**: CRITICAL | **Effort**: MEDIUM | **Blocks**: Binary/base64 handling

**Tinker Pattern**: `@field_serializer("data")` for base64 encoding on output.

**Required Change**:
```elixir
{:data, :binary, [
  required: true,
  on_serialize: &Base.encode64/1
]}
```

---

## 3. High Priority Gaps

### GAP-007: Field Alias Support in Sinter
**Severity**: HIGH | **Effort**: MEDIUM | **Blocks**: JSON wire compatibility

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_utils/_transform.py`):
```python
card_id: Annotated[str, PropertyInfo(alias="cardID")]
```

**Current Sinter**: Aliases only in Transform options, not schema definition.

**Required Change**:
```elixir
{:account_holder_name, :string, [required: true, alias: "accountHolderName"]}
```

**Implementation Locations**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex:99-117` (add to opts schema)
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex` (lookup by alias)

---

### GAP-008: Enhanced Codegen - Docstrings
**Severity**: HIGH | **Effort**: LOW | **Blocks**: Developer experience

**Tinker Pattern**: Full docstrings in resource methods.

**Current Pristine** (`/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`):
```elixir
def #{fn_name}(payload, context, opts \\ []) do
  Pristine.Runtime.execute(@manifest, #{inspect(fn_name)}, payload, context, opts)
end
```

**Required Change**:
```elixir
@doc """
#{endpoint.description}

## Parameters
  * `request` - #{endpoint.request} struct
  * `context` - Runtime context
  * `opts` - Request options
"""
@spec #{fn_name}(map(), Context.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
def #{fn_name}(request, context, opts \\ []) do
  ...
end
```

---

### GAP-009: Enhanced Codegen - Resource Grouping
**Severity**: HIGH | **Effort**: MEDIUM | **Blocks**: SDK ergonomics

**Tinker Pattern**: `client.models.create()`, `client.sampling.sample()`

**Current Pristine**: All endpoints in single module.

**Required Change**:
- Add `resource` field to Endpoint struct
- Generate one module per resource
- Generate client with resource accessors

---

### GAP-010: Enhanced Codegen - Typespecs
**Severity**: HIGH | **Effort**: LOW | **Blocks**: Dialyzer support

**Current**: No @spec on generated functions.

**Required**: Generate @spec from manifest request/response types.

---

### GAP-011: Retry-After Header Parsing
**Severity**: HIGH | **Effort**: LOW | **Blocks**: Proper rate limit handling

**Tinker Pattern** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py:683-706`):
```python
retry_after = self._parse_retry_after_header(response_headers)
if retry_after is not None and 0 < retry_after <= 60:
    return retry_after
```

**Current Pristine**: Foundation supports `retry_after_ms_fun` but not wired.

**Required Change**: Create `Foundation.Retry.HTTP.parse_retry_after/1` and wire through pipeline.

---

### GAP-012: Connection/Concurrency Limiting
**Severity**: HIGH | **Effort**: MEDIUM | **Blocks**: Resource protection

**Tinker Pattern**: `asyncio.Semaphore(config.max_connections)`

**Foundation Has**: `Foundation.Semaphore.Counting`, `Foundation.Semaphore.Weighted`

**Required Change**:
- New `Pristine.Ports.Semaphore` behaviour
- New `Pristine.Adapters.Semaphore.Counting`
- Wire into pipeline

---

### GAP-013: Manifest Validation Mix Task
**Severity**: HIGH | **Effort**: LOW | **Blocks**: Developer workflow

**Required**: `mix pristine.validate --manifest path/to/manifest.json`

---

### GAP-014: OpenAPI Generation
**Severity**: HIGH | **Effort**: MEDIUM | **Blocks**: Documentation, client generation

**Required**: `mix pristine.openapi --manifest path/to/manifest.json`

Leverage Sinter's `JsonSchema` module for schema generation.

---

## 4. Medium Priority Gaps

### GAP-015: Literal Type in Sinter
**Severity**: MEDIUM | **Effort**: LOW

**Tinker**: `type: Literal["sample"] = "sample"`

**Current Sinter**: Only `choices: ["sample"]` which is verbose.

**Required**: `{:literal, "sample"}` type.

---

### GAP-016: Bytes Type in Sinter
**Severity**: MEDIUM | **Effort**: LOW

**Tinker**: Native `bytes` type with base64 serialization.

**Required**: `{:bytes, []}` type with auto base64 handling.

---

### GAP-017: Idempotency Header Support
**Severity**: MEDIUM | **Effort**: LOW

**Tinker**: `idempotency_key` in request options.

**Required**:
- Add `idempotency` field to Endpoint
- Add `idempotency_header` to Context
- Generate UUID in pipeline when enabled

---

### GAP-018: Error Module with Status Codes
**Severity**: MEDIUM | **Effort**: MEDIUM

**Tinker** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py:234-265`):
```python
if response.status_code == 400:
    return BadRequestError(...)
if response.status_code == 401:
    return AuthenticationError(...)
```

**Required**: `Pristine.Error` module with status-specific types.

---

### GAP-019: Session-Scoped Telemetry Reporter
**Severity**: MEDIUM | **Effort**: HIGH

**Tinker** (`/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/telemetry.py`):
- Event batching
- Session start/end
- Exception capture
- Backend reporting

**Reference**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter.ex`

---

### GAP-020: Telemetry Measure/Span in Port
**Severity**: MEDIUM | **Effort**: LOW

**Foundation Has**: `Telemetry.measure/3`, `Telemetry.emit_counter/2`

**Current Port**: Only `emit/3`.

**Required**: Add `measure/3`, `emit_counter/2`, `emit_gauge/3` to port.

---

### GAP-021: Multipart Streaming in Adapter
**Severity**: MEDIUM | **Effort**: LOW

**MultipartEx Has**: Full streaming support, content-length calculation.

**Current Adapter**: Doesn't expose these capabilities.

**Required**: Add `build_streaming/2`, `content_length/2` to port/adapter.

---

### GAP-022: File Input Transform Layer
**Severity**: MEDIUM | **Effort**: MEDIUM

**Tinkex Has**: `Tinkex.Files.Transform` for input normalization.

**Required**: `Pristine.Files` module with `transform/1`, `transform_async/1`.

---

### GAP-023: Documentation Generation Mix Task
**Severity**: MEDIUM | **Effort**: MEDIUM

**Required**: `mix pristine.docs --manifest path/to/manifest.json`

---

### GAP-024: Test Fixtures Module
**Severity**: MEDIUM | **Effort**: LOW

**Required**: `Pristine.Test.Fixtures` with `sample_manifest/1`, `sample_context/1`.

---

### GAP-025: Mock Server Generation
**Severity**: MEDIUM | **Effort**: MEDIUM

**Required**: Generate Plug router from manifest for testing.

---

### GAP-026: Dialyzer Configuration
**Severity**: MEDIUM | **Effort**: LOW

**Required**: Add dialyxir to deps, create .dialyzer_ignore.exs.

---

### GAP-027: Credo Configuration
**Severity**: MEDIUM | **Effort**: LOW

**Required**: Add credo to deps, create .credo.exs.

---

## 5. Low Priority Gaps

### GAP-028: Base64 Format in Sinter.Transform
**Severity**: LOW | **Effort**: LOW

**Required**: Add `:base64` format option.

---

### GAP-029: Async File Reading
**Severity**: LOW | **Effort**: LOW

**Tinker**: `anyio` async file reading.

**MultipartEx**: Synchronous but streaming.

**Required**: Optional `Task.async` wrapper.

---

### GAP-030: Validation Input Module in MultipartEx
**Severity**: LOW | **Effort**: LOW

**Required**: `Multipart.Validation` with type guards.

---

### GAP-031: Default Base URL in Context
**Severity**: LOW | **Effort**: LOW

**Tinker**: Hardcoded default with env var override.

**Required**: Default value support in Context.

---

### GAP-032: Credential Validation
**Severity**: LOW | **Effort**: LOW

**Tinker**: `api_key.startswith("tml-")` check.

**Required**: Add validation callback to auth adapters.

---

### GAP-033: Env Var Fallback in Context
**Severity**: LOW | **Effort**: LOW

**Tinker**: `os.environ.get("TINKER_API_KEY")`

**Required**: `Context.from_env/1` or similar.

---

### GAP-034: Version Command/Function
**Severity**: LOW | **Effort**: LOW

**Required**: `Pristine.version/0` and/or Mix task.

---

---

## 6. Gap Dependencies

```
GAP-001 (Discriminated Unions)
    └─ Blocks: Type validation for unions

GAP-002 (SSE/Streaming)
    ├─ Requires: New transport port
    ├─ Requires: New response type
    └─ Blocks: All streaming endpoints

GAP-003 (Future/Polling)
    ├─ Requires: GAP-011 (Retry-After)
    └─ Blocks: All async operations

GAP-004 (Pre-validation) ─┬─ Blocks: Complex type transforms
GAP-005 (Field validators) ┘

GAP-007 (Field aliases)
    └─ Blocks: JSON wire compatibility

GAP-008/009/010 (Codegen)
    └─ Blocks: Developer experience

GAP-013 (Validation task)
    └─ Blocks: GAP-014 (OpenAPI task)
```

---

## 7. Effort Estimates

| Effort Level | Definition | Gap Count |
|--------------|------------|-----------|
| LOW | < 1 day, localized change | 14 |
| MEDIUM | 1-3 days, some refactoring | 12 |
| HIGH | 3-5 days, significant new code | 5 |
| CRITICAL (HIGH) | 5+ days, architectural | 3 |

**Total Estimated Effort**: ~40-50 developer days

---

## 8. Gap-to-Feature Mapping

| Tinker Feature | Required Gaps |
|----------------|---------------|
| `client.models.create()` style | GAP-009, GAP-008, GAP-010 |
| Streaming responses | GAP-002 |
| Async futures | GAP-003, GAP-011 |
| Discriminated unions in types | GAP-001 |
| Complex type transforms | GAP-004, GAP-005, GAP-006 |
| JSON field aliases | GAP-007 |
| Rate limit handling | GAP-011, GAP-012 |
| Idempotent requests | GAP-017 |
| Type-safe errors | GAP-018 |
| Full telemetry | GAP-019, GAP-020 |
| File uploads | GAP-021, GAP-022 |
| Developer tooling | GAP-013, GAP-014, GAP-023, GAP-024, GAP-025 |
| Code quality | GAP-026, GAP-027 |

---

## 9. Risk Assessment

### High Risk Gaps

| Gap | Risk | Mitigation |
|-----|------|------------|
| GAP-001 | Sinter breaking change | Feature flag, maintain backward compat |
| GAP-002 | Complex new subsystem | Port from Tinkex, extensive testing |
| GAP-003 | Complex state management | Port from Tinkex, GenServer based |

### Medium Risk Gaps

| Gap | Risk | Mitigation |
|-----|------|------------|
| GAP-004 | Validation order changes | Comprehensive test suite |
| GAP-009 | Codegen restructure | Incremental rollout |

### Low Risk Gaps

Most other gaps are additive features with clear implementations.

---

## 10. Quick Wins

These gaps can be addressed in < 1 day each:

1. **GAP-008**: Add @doc to codegen (string interpolation)
2. **GAP-010**: Add @spec to codegen (string interpolation)
3. **GAP-015**: Add {:literal, value} to Sinter types
4. **GAP-017**: Add idempotency header logic
5. **GAP-013**: Create validation Mix task shell
6. **GAP-026**: Add dialyxir to deps
7. **GAP-027**: Create .credo.exs

**Impact**: Improves developer experience significantly with minimal effort.
