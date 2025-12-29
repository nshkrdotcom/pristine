# Summary of Tinkex 20251227 Prior Work Analysis

## Overview

This document summarizes the comprehensive planning and design work from December 27, 2025, which established the foundation for extracting reusable libraries from Tinkex to support Pristine's SDK generation architecture.

---

## 1. Problems Being Solved

### Foundation Resilience
- **Duplication Crisis**: Retry/backoff logic scattered across 8+ modules
- **Inconsistent Semantics**: Different jitter strategies, attempt counting methods
- **Testing Difficulty**: Lack of injectable RNG and sleep functions
- **Global Collisions**: ETS registry issues without explicit naming

### Multipart/Files Library
- **Implicit Path Vulnerability**: Strings with `/` or `.` treated as file paths (LFI risk)
- **OOM Risk**: Full body concatenation into memory
- **Rigid Serialization**: Hardcoded bracket notation incompatible with many backends
- **Memory Inefficiency**: No streaming support

### Telemetry Reporter
- **Reporter Gap**: No vendor-agnostic batching system
- **Synchronous Dispatch**: Blocking I/O in telemetry handlers
- **Unbounded Queues**: No backpressure or memory protection
- **Data Loss**: No graceful shutdown or drain semantics

### TikToken Extraction
- **Inflated Tinkex**: HuggingFace resolution scattered across codebase
- **Coupling**: tiktoken_ex was incomplete; HF download logic was Tinkex-specific

### Sinter Refactor
- **Manual Schema Handling**: Bespoke Jason.Encoder implementations
- **Duplicated Parsing**: Many from_json/1 parsers duplicating logic
- **Inconsistent Nullability**: Manual nil vs omit handling

---

## 2. Integrations Planned

```
Foundation <- Tinkex: Extract backoff, retry, semaphores, circuit breakers
multipart_ex <- Tinkex: Extract multipart encoding with safety fixes
telemetry_reporter <- Tinkex: Extract reporter using Pachka
tiktoken_ex <- Tinkex: Add HuggingFace file resolution and caching
Tinkex <- Sinter: Replace manual schemas with Sinter.Schema
Pristine <- All: Consume unified libraries for SDK generation
```

---

## 3. Architectural Decisions

### Foundation Resilience v2 (Final Design)

**Backoff**:
- Pure calculation functions + `Policy` struct
- Strategies: exponential, linear, constant
- Jitter variants: factor, additive, range, none

**Retry**:
- Separate `Policy` and `State` for manual/testing control
- `max_attempts`, `max_elapsed_ms`, `retry_on` predicate, `progress_timeout_ms`

**RateLimit.BackoffWindow**:
- ETS + `:atomics` per key
- Shared backoff windows across clients

**Semaphore**:
- Counting: ETS-based, non-blocking
- Weighted: GenServer-backed, allows negative budget

**CircuitBreaker**:
- State machine: closed/open/half-open
- Optional ETS registry + CAS updates

**Determinism**:
- All primitives accept injectable `rand_fun` and `sleep_fun`

**Dependencies**:
- Stdlib + `:telemetry` only
- Removed: `:fuse`, `:hammer`, `:poolboy`, `:semaphore`

### Multipart/Files (multipart_ex)

- **Strict Safety**: Explicit `{:path, path}` tuples
- **Streaming First**: `Stream.t()` support for large uploads
- **Pluggable Serialization**: `:bracket`, `:dot`, `:flat` strategies
- **Client Agnostic**: Separate adapters for Finch and Req (Tesla/Hackney planned)
- **Part Model**: `Multipart.Part` struct with body, headers, Content-Disposition

### TelemetryReporter

- **Pachka-Based**: Message batching with time/size dual triggers
- **Sink Pattern**: Transport-agnostic delivery
- **Load Shedding**: Drops new messages on overflow
- **Poison Pill Safety**: Isolates malformed events
- **Graceful Shutdown**: Explicit drain via `flush(sync?: true)` / `wait_until_drained`; `stop/2` delegates to Pachka

### TikToken Integration

- **Generic HF Resolution**: `TiktokenEx.HuggingFace.resolve_file/4` with filesystem cache
- **Atomic Writes**: Download to temp file then rename
- **Path Sanitization**: Prevents `../` traversal
- **Injection Points**: `fetch_fun` for testing

> **Note**: tiktoken_ex uses filesystem-based caching (not ETS) to persist
> downloaded tokenizer files across application restarts.

### Sinter Refactor

- **String Keys Everywhere**: Safe for untrusted input
- **Schema Definitions**: `Sinter.Schema.define/2` per type
- **NotGiven Semantics**: Only `Sinter.NotGiven` stripped; nil preserved
- **Nested Objects**: `Schema.object/1` and `{:object, schema}`

---

## 4. Relation to Pristine

Pristine's recent commits show alignment:
- **Semaphore port** (206a894): Resource-based endpoint grouping
- **Resource-based endpoints** (23eedc1): SDK-style API grouping
- **Streaming/Future adapters** (926f811): Streaming transport and polling
- **Core architecture** (7d11502): Foundation established

**The Tinkex work enables Pristine to:**
1. Use Foundation for decoupled resilience
2. Leverage multipart_ex for safe file uploads
3. Use telemetry_reporter for batch event collection
4. Use tiktoken_ex for tokenizer support
5. Use Sinter schemas for generated types
6. Apply client-agnostic patterns for SDK generation

---

## 5. Gaps and Concerns

### Foundation Gaps
- Weighted semaphore modes (negative budget vs strict)?
- `max_elapsed_ms` default or opt-in?
- Retry-after parsing location?

### Multipart Gaps
- Ring buffer option for drop-old semantics (v2)
- `Multipart.Part` convenience builders
- MIME type inference (optional external dependency)

### Telemetry Reporter Gaps
- Drop policy: new vs old
- Ring-buffer mode deferred
- Pre-aggregation layer not included
- Default HTTP transport is example only

### TikToken Gaps
- Private repo auth tokens not supported
- Cache sharing with huggingface_hub unresolved

### Sinter Integration Gaps
- Output key shape (string keys, no atom leaks)
- Nil semantics (preserve Python parity)
- Performance in hot paths

### General Risks
- **Behavior Drift**: Python parity via explicit policy options
- **Global Collisions**: Explicit ETS initialization
- **Performance**: Pure backoff calculations
- **Test Compatibility**: Injected functions for determinism

---

## 6. Key Insight

The 20251227 work represents a major refactoring to **extract reusable, generic libraries** that serve both Tinkex itself and Pristine's SDK generation. Each library:
- Solves a specific problem
- Maintains behavioral parity with Python SDK
- Adds safety and performance improvements
- Remains client-agnostic for broad applicability

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinkex 20251227 documentation*
