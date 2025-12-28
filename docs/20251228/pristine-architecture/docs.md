# Pristine Architecture and Tinker Mapping (2025-12-28)

## Purpose
Pristine is a manifest-driven, hexagonal core that generates Elixir SDKs and
service clients. It replaces hand-wired plumbing (types, resource clients,
retries, telemetry, multipart) with a declarative manifest + codegen pipeline.
Tinkex becomes an instance of the system rather than bespoke code.

This document captures:
- What is implemented in Pristine today
- The architecture boundaries and runtime flow
- How Tinker’s Python SDK structure maps into Pristine’s generalized system
- What remains to be built to fully generalize Tinker/Tinkex

## Scope and Repos
- Pristine core: `/home/home/p/g/n/pristine`
- Sinter (schema validation/JSON schema): `/home/home/p/g/n/sinter`
- Foundation (retry/backoff/circuit breaker/backoff window): `/home/home/p/g/n/foundation`
- Multipart_ex (multipart encoding): `/home/home/p/g/n/multipart_ex`
- Telemetry_reporter (batched telemetry, Pachka): `/home/home/p/g/n/telemetry_reporter`
- Tiktoken_ex (tokenizer glue): `/home/home/p/g/North-Shore-AI/tiktoken_ex`
- Tinker SDK (source for mapping): `/home/home/p/g/North-Shore-AI/tinker`

## What Pristine Includes Today
### Core Runtime
- Manifest normalization and validation
  - `/home/home/p/g/n/pristine/lib/pristine/manifest.ex`
  - `/home/home/p/g/n/pristine/lib/pristine/manifest/schema.ex`
  - `/home/home/p/g/n/pristine/lib/pristine/manifest/loader.ex`
- Request pipeline
  - `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`
- URL building + path/query handling
  - `/home/home/p/g/n/pristine/lib/pristine/core/url.ex`
- Header building + auth aggregation
  - `/home/home/p/g/n/pristine/lib/pristine/core/headers.ex`
  - `/home/home/p/g/n/pristine/lib/pristine/core/auth.ex`
- Type compilation (manifest -> Sinter schemas)
  - `/home/home/p/g/n/pristine/lib/pristine/core/types.ex`

### Ports (Interfaces)
- Transport: `/home/home/p/g/n/pristine/lib/pristine/ports/transport.ex`
- Serializer: `/home/home/p/g/n/pristine/lib/pristine/ports/serializer.ex`
- Retry: `/home/home/p/g/n/pristine/lib/pristine/ports/retry.ex`
- Telemetry: `/home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex`
- Auth: `/home/home/p/g/n/pristine/lib/pristine/ports/auth.ex`
- Multipart: `/home/home/p/g/n/pristine/lib/pristine/ports/multipart.ex`
- Circuit breaker: `/home/home/p/g/n/pristine/lib/pristine/ports/circuit_breaker.ex`
- Rate limit: `/home/home/p/g/n/pristine/lib/pristine/ports/rate_limit.ex`
- Tokenizer: `/home/home/p/g/n/pristine/lib/pristine/ports/tokenizer.ex`

### Adapters (Concrete Implementations)
- Finch transport: `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex`
- JSON serializer (Jason + Sinter): `/home/home/p/g/n/pristine/lib/pristine/adapters/serializer/json.ex`
- Retry via Foundation: `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex`
- Circuit breaker via Foundation: `/home/home/p/g/n/pristine/lib/pristine/adapters/circuit_breaker/foundation.ex`
- Rate limit via Foundation backoff window: `/home/home/p/g/n/pristine/lib/pristine/adapters/rate_limit/backoff_window.ex`
- Multipart via multipart_ex: `/home/home/p/g/n/pristine/lib/pristine/adapters/multipart/ex.ex`
- Telemetry via telemetry_reporter: `/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/reporter.ex`
- Tokenizer via tiktoken_ex: `/home/home/p/g/n/pristine/lib/pristine/adapters/tokenizer/tiktoken.ex`
- No-op adapters for retry/telemetry/rate limit

### Codegen
- Elixir source rendering from manifest: `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`
- Codegen orchestration + write to disk: `/home/home/p/g/n/pristine/lib/pristine/codegen.ex`
- Mix task: `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.generate.ex`

### Example App
- End-to-end demo using Finch + Plug: `/home/home/p/g/n/pristine/examples/demo.exs`

## Architecture Summary
Pristine is a ports-and-adapters system with a manifest-driven compiler.

### High-Level Flow
1. Manifest is loaded and normalized.
2. Manifest types are compiled into Sinter schemas.
3. Pipeline executes endpoint:
   - Build headers (base + endpoint + auth + extras + content-type)
   - Build URL (base + path + path params + query)
   - Encode body (JSON or multipart)
   - Apply retry + rate limit + circuit breaker
   - Send via transport
   - Decode response and validate with Sinter

### Ports and Adapters Boundary
- Core never depends on HTTP, JSON, or telemetry libraries directly.
- Adapters encapsulate all IO or library-specific behavior.
- Swapping adapters changes the runtime behavior without changing manifests.

## Mapping from Tinker to Pristine
Tinker (Python SDK) is structured like a typical generated client. Most files map
cleanly to manifests, ports, adapters, and codegen in Pristine.

### 1) Types and Schema Models
**Tinker location:**
- `src/tinker/types/*.py`
- `src/tinker/_models.py` (Pydantic base)

**Pristine mapping:**
- Manifest `types` map + Sinter compilation.
- Manifest fields -> `Sinter.Schema.define/1` via `Pristine.Core.Types`.

**Result:**
- Pydantic models become generated Sinter schemas and Elixir structs.

### 2) Resource Clients / Methods
**Tinker location:**
- `src/tinker/resources/*.py`
- `src/tinker/_resource.py`

**Pristine mapping:**
- Manifest `endpoints` definitions.
- Codegen renders client modules from endpoints.

**Result:**
- Resource methods become generated client functions.

### 3) Base Client
**Tinker location:**
- `src/tinker/_client.py`
- `src/tinker/_base_client.py`

**Pristine mapping:**
- `Pristine.Core.Context` holds configuration (base_url, headers, adapters).
- `Pristine.Core.Pipeline` executes requests.

**Result:**
- Base client config maps into context + pipeline.

### 4) Serialization and Validation
**Tinker location:**
- `src/tinker/_response.py`
- `src/tinker/_utils/_transform.py`

**Pristine mapping:**
- `Pristine.Adapters.Serializer.JSON` + Sinter validation.
- `Pristine.Core.Types` builds schemas for validation.

**Result:**
- Response validation moves from Pydantic to Sinter.

### 5) Multipart / Files
**Tinker location:**
- `src/tinker/_files.py`

**Pristine mapping:**
- `Pristine.Adapters.Multipart.Ex` (multipart_ex).

**Result:**
- Multipart encoding becomes a reusable adapter.

### 6) Streaming / Futures
**Tinker location:**
- `src/tinker/_streaming.py`
- `src/tinker/resources/futures.py`

**Pristine mapping:**
- Pipeline supports streaming flags but streaming adapters are not yet built.

**Result:**
- Streaming is a gap; needs a `Ports.Streaming` adapter and manifest policy.

### 7) Retry / Resilience
**Tinker location:**
- `src/tinker/lib/retry_handler.py`

**Pristine mapping:**
- `Pristine.Adapters.Retry.Foundation`
- Circuit breaker + rate limiting adapters

**Result:**
- Retry/backoff/circuit breaker are generalized and reusable.

### 8) Telemetry
**Tinker location:**
- `src/tinker/lib/telemetry.py`
- `src/tinker/lib/telemetry_provider.py`

**Pristine mapping:**
- `Pristine.Adapters.Telemetry.Reporter` (telemetry_reporter)

**Result:**
- Batched, generic telemetry shipping as adapter.

### 9) Auth / Headers
**Tinker location:**
- `_client.py` uses API key and default headers

**Pristine mapping:**
- `Pristine.Adapters.Auth.ApiKey` / `Bearer`
- `Pristine.Core.Headers` merges base + endpoint + auth + extras

**Result:**
- Auth becomes fully pluggable with per-endpoint overrides.

### 10) Utilities and Helpers
**Tinker location:**
- `_utils/*` (query string, helpers, resources proxy)

**Pristine mapping:**
- `Pristine.Core.Url` for query/path handling
- Manifest directives for pagination, streaming, or special behaviors

**Result:**
- Most utilities can be replaced by core primitives.

## Manifest-to-Codegen Mapping
### Endpoint Definition
Manifest:
```
%{id: "sample", method: "POST", path: "/sampling", request: "SampleRequest"}
```
Generated client:
```
def sample(payload, context, opts \\ []) do
  Pristine.Runtime.execute(@manifest, "sample", payload, context, opts)
end
```

### Type Definition
Manifest:
```
"SampleRequest" => %{fields: %{prompt: %{type: "string", required: true}}}
```
Generated schema:
```
Sinter.Schema.define([
  {"prompt", :string, [required: true]}
])
```

## Gaps and Planned Extensions
1. Streaming adapter and API
   - Need a `Ports.Streaming` or streaming-capable transport
   - Manifest `streaming: true` should influence transport behavior
2. Rich type composition
   - Support nested objects, unions, and discriminators in manifest types
3. Manifest policies
   - Global defaults for retry, rate limit, auth, telemetry
   - Per-endpoint overrides for all policies
4. Generated structs
   - Optionally emit struct modules alongside schema modules
5. JSON Schema and provider transforms
   - Integrate Sinter JSON Schema for external tooling
6. CLI and docs generation
   - Manifest-driven documentation output and examples

## Why This is a Good Generalization
- Tinker already looks generated (resource classes and types are repetitive).
- Manifest definitions capture 80-90% of Tinker’s code as declarative data.
- Ports/adapters make the core reusable beyond any ML-specific API.

## Summary
Pristine now implements a working manifest-driven core with adapters for
transport, retry/backoff, telemetry, multipart, and tokenization. The remaining
work is to expand manifest expressiveness (streaming, unions, nested objects)
and codegen outputs (structs, docs). This positions Pristine as a reusable SDK
generator that can render Tinkex as configuration rather than code.
