# Pristine Salvage Assessment

**Date**: 2026-01-06
**Purpose**: Determine what's worth keeping from current pristine before pivoting strategy

## Executive Summary

**Current pristine has significant value** in its core infrastructure. The problem is `examples/tinkex` - it's a direct port that doesn't use pristine properly.

### Verdict: SALVAGE THE CORE, ABANDON THE EXAMPLE

| Component | Lines | Verdict | Reason |
|-----------|-------|---------|--------|
| `lib/pristine/` | 4,686 | **KEEP** | Well-designed hexagonal architecture |
| `examples/tinkex/` | 22,357 | **ABANDON** | Doesn't use pristine, defeats the purpose |
| `test/pristine/` | 13,174 | **KEEP** | 354 passing tests, validates core |

---

## What's Valuable in Pristine Core

### 1. Pipeline Composition (562 lines) - EXCELLENT

`lib/pristine/core/pipeline.ex` implements elegant resilience stack composition:

```elixir
# Functional nesting: retry → rate_limit → circuit_breaker → transport
retry(fn ->
  rate_limit(fn ->
    circuit_breaker(fn ->
      transport(request)
    end)
  end)
end)
```

**Why it's good:**
- Clean separation of cross-cutting concerns
- Each layer is independently testable
- Context threading is transparent
- No mutation, pure functional composition

### 2. Manifest System (508 lines) - GOOD

`lib/pristine/manifest.ex` handles:
- 33 endpoint fields (method, auth, timeout, streaming, etc.)
- Type unions with discriminators
- Per-endpoint retry policies, rate limits, circuit breakers
- Response unwrapping, error type mapping
- Idempotency configuration

**Why it's good:**
- Single source of truth for API definition
- Comprehensive normalization and validation
- Clear error messages on invalid manifests

### 3. Code Generation (1,100+ lines) - EXCELLENT

Production-quality SDK generator:

- **Type Generation** (`codegen/type.ex`, 789 lines)
  - Full struct + typespec + Sinter schema
  - Union types with discriminator-based decode
  - Recursive encode/decode for nested types

- **Resource Generation** (`codegen/resource.ex`, 623 lines)
  - One function per endpoint (sync/async/stream)
  - Automatic path parameter extraction
  - Type-safe execution

- **Client Generation** (`codegen/elixir.ex`, 251 lines)
  - Top-level client struct
  - Resource accessors
  - Manifest embedding

### 4. Port Definitions (12 ports, ~150 lines) - GOOD

Well-defined behavior contracts:
- Transport, Serializer, Retry, RateLimit
- CircuitBreaker, Auth, Telemetry, Tokenizer
- Future, StreamTransport, Multipart, Semaphore

**Why they're good:**
- Minimal, focused interfaces
- No god objects
- Clear compile-time contracts

### 5. Foundation Adapters (~500 lines) - GOOD

Integration with foundation library:
- Retry with exponential backoff
- Circuit breaker with failure thresholds
- Telemetry event emission
- Rate limiting

### 6. SSE/Streaming (311 lines) - EXCELLENT

- **SSEDecoder** (200 lines) - RFC-compliant, stateful, incremental
- **StreamResponse** (109 lines) - Lazy enumerable with cancel hooks
- **FinchStream** (273 lines) - Task-based background streaming

### 7. Error Classification (227 lines) - GOOD

Maps HTTP status → semantic error types with `retriable?` checks.

---

## What's Missing from Pristine

To support tinkex properly, pristine needs:

### 1. BytesSemaphore Port/Adapter
Tinkex needs byte-budget rate limiting (not just request count).

### 2. Session Management Port
Long-running connections with lifecycle management.

### 3. Compression Port/Adapter
Gzip compression for large payloads.

### 4. Environment Utilities
Runtime config from env vars with validation.

### 5. Future Polling Refinements
Tinkex's async operation model is unique - may need protocol support.

---

## What's Wrong with examples/tinkex

**It's 22,357 lines of code that barely uses pristine.**

Only ONE module imports pristine:
```elixir
# Tinkex.Streaming.SampleStream
alias Pristine.Streaming.{SSEDecoder, Event}
```

Everything else is handwritten:
- Custom HTTP transport (should use Pristine.Adapters.Transport.Finch)
- Custom retry logic (should use Pristine.Adapters.Retry.Foundation)
- Custom telemetry (should use Pristine.Adapters.Telemetry.Foundation)
- Custom rate limiting (should use foundation via port)
- Custom serialization (should use Pristine.Adapters.Serializer.JSON)

**The manifest exists but is not used to drive the SDK.**

---

## Recommended Path Forward

### Option A: Salvage Pristine Core, Rebuild Tinkex (RECOMMENDED)

1. **Keep** `lib/pristine/` as-is
2. **Delete** `examples/tinkex/` entirely
3. **Add** missing ports to pristine (bytes semaphore, compression, etc.)
4. **Refactor** original tinkex (~/p/g/North-Shore-AI/tinkex) in place
5. **Migrate** original tinkex to use pristine ports/adapters
6. **Generate** tinkex SDK from manifest when ready

**Pros:**
- Pristine core is validated with 354 tests
- Don't throw away good work
- Clear separation of concerns

**Cons:**
- More complex migration path
- Need to maintain two repos during transition

### Option B: Start Fresh in Original Tinkex

1. **Abandon** this pristine entirely
2. **Refactor** original tinkex iteratively
3. **Extract** generalizations into new pristine
4. **Build** manifest system after patterns emerge

**Pros:**
- Simpler mental model
- Everything in one place during refactor

**Cons:**
- Loses 4,686 lines of tested infrastructure
- Re-implements manifest system from scratch
- Re-implements code generation from scratch

---

## Conclusion

**Pristine core is worth keeping.** The architecture is sound:
- Hexagonal design is properly implemented
- Code generation is production-quality
- Tests all pass (354/354)
- Foundation integration works

**The example is worthless.** Delete it.

The right approach:
1. Keep pristine core
2. Add missing ports for tinkex use cases
3. Refactor original tinkex to use pristine infrastructure
4. Original tinkex becomes thin: manifest + config + domain-specific logic
