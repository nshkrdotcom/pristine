# Pristine Architecture Audit: Implementation Roadmap

**Date**: 2025-12-28
**Status**: Staged Implementation Plan Complete

---

## 1. Roadmap Overview

This roadmap outlines a staged approach to bring Pristine to full Tinker SDK parity, enabling complete Tinkex generation from manifests + adapters.

### Stages Summary

| Stage | Focus | Effort | Dependencies |
|-------|-------|--------|--------------|
| **Stage 0** | Quick Wins | 3-5 days | None |
| **Stage 1** | Type System Parity | 8-10 days | Stage 0 |
| **Stage 2** | Streaming Infrastructure | 7-10 days | Stage 0 |
| **Stage 3** | Codegen Enhancement | 5-7 days | Stage 1 |
| **Stage 4** | Resilience Completion | 4-6 days | Stage 0 |
| **Stage 5** | Developer Tooling | 5-8 days | Stages 1-3 |
| **Stage 6** | Integration & Polish | 5-7 days | All |

**Total Estimated Effort**: 37-53 days

---

## 2. Stage 0: Quick Wins (3-5 days)

**Goal**: Immediate improvements with minimal risk.

### 0.1 Codegen Documentation (1 day)

**Gaps Addressed**: GAP-008, GAP-010

**Changes**:
- Add @doc generation from endpoint description
- Add @spec generation from request/response types

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`

**Tests**:
```elixir
describe "render_endpoint_fn/1" do
  test "generates @doc from description" do
    endpoint = %Endpoint{id: :test, description: "Test endpoint"}
    code = ElixirCodegen.render_endpoint_fn(endpoint)
    assert code =~ ~s(@doc "Test endpoint")
  end
end
```

### 0.2 Literal Type in Sinter (0.5 day)

**Gap Addressed**: GAP-015

**Changes**:
- Add `{:literal, value}` to type specs
- Validate exact match
- Generate `{"const": value}` in JSON Schema

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/types.ex`
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

**Tests**:
```elixir
test "validates literal value" do
  assert {:ok, "sample"} = Types.validate({:literal, "sample"}, "sample", [])
  assert {:error, _} = Types.validate({:literal, "sample"}, "other", [])
end
```

### 0.3 Validation Mix Task Shell (1 day)

**Gap Addressed**: GAP-013

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.validate.ex`

**Implementation**:
```elixir
defmodule Mix.Tasks.Pristine.Validate do
  use Mix.Task

  @shortdoc "Validate a Pristine manifest"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [manifest: :string, format: :string])
    manifest_path = Keyword.fetch!(opts, :manifest)

    case Pristine.Manifest.load_file(manifest_path) do
      {:ok, _manifest} ->
        Mix.shell().info("Manifest is valid")
      {:error, errors} ->
        format_errors(errors, Keyword.get(opts, :format, "text"))
        exit({:shutdown, 1})
    end
  end
end
```

### 0.4 Dialyzer/Credo Setup (0.5 day)

**Gaps Addressed**: GAP-026, GAP-027

**Files to Modify**:
- `/home/home/p/g/n/pristine/mix.exs` (add deps)

**Files to Create**:
- `/home/home/p/g/n/pristine/.credo.exs`

### 0.5 Idempotency Header (0.5 day)

**Gap Addressed**: GAP-017

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex` (add field)
- `/home/home/p/g/n/pristine/lib/pristine/core/context.ex` (add header config)
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex` (add header logic)

---

## 3. Stage 1: Type System Parity (8-10 days)

**Goal**: Bring Sinter to full Pydantic feature parity for Tinker types.

### 1.1 Discriminated Union Support (3-4 days)

**Gap Addressed**: GAP-001

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/types.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

**New Type Syntax**:
```elixir
{:discriminated_union, [
  discriminator: "type",
  variants: %{
    "encoded_text" => EncodedTextChunk.schema(),
    "image" => ImageChunk.schema()
  }
]}
```

**Implementation Steps**:
1. Add type spec to `Sinter.Types`
2. Implement `validate_discriminated_union/3`
3. Extract discriminator value from data
4. Look up variant schema
5. Validate against variant
6. Generate JSON Schema with `discriminator` keyword

**Tests**:
```elixir
describe "discriminated union" do
  test "validates correct variant" do
    schema = build_discriminated_union_schema()
    data = %{"type" => "image", "data" => "base64..."}
    assert {:ok, _} = Validator.validate(schema, data)
  end

  test "returns error for unknown discriminator" do
    schema = build_discriminated_union_schema()
    data = %{"type" => "unknown"}
    assert {:error, [%{code: :unknown_discriminator}]} = Validator.validate(schema, data)
  end
end
```

### 1.2 Pre-validation Hooks (2 days)

**Gap Addressed**: GAP-004

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`

**API**:
```elixir
Schema.define([...], pre_validate: fn data ->
  # Transform before validation
  update_in(data, ["field"], &transform/1)
end)
```

**Implementation**:
```elixir
# In Validator.validate/3
def validate(%Schema{} = schema, data, opts) do
  data = apply_pre_validation(schema, data)
  # ... rest of validation
end

defp apply_pre_validation(%Schema{config: %{pre_validate: nil}}, data), do: data
defp apply_pre_validation(%Schema{config: %{pre_validate: fun}}, data), do: fun.(data)
```

### 1.3 Field-level Validators (2 days)

**Gap Addressed**: GAP-005

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex` (add `:validate` to field opts)
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex` (call validator)

**API**:
```elixir
{:email, :string, [required: true, validate: &validate_email/1]}

def validate_email(value) do
  if String.contains?(value, "@"),
    do: {:ok, value},
    else: {:error, "must contain @"}
end
```

### 1.4 Field Aliases (2 days)

**Gap Addressed**: GAP-007

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`
- `/home/home/p/g/n/sinter/lib/sinter/transform.ex`

**API**:
```elixir
{:account_name, :string, [required: true, alias: "accountName"]}
```

**Implementation**:
- Schema stores alias mapping
- Validator looks up by alias or canonical name
- Transform uses alias for output

---

## 4. Stage 2: Streaming Infrastructure (7-10 days)

**Goal**: Full SSE streaming and future/polling support.

### 2.1 SSE Decoder (2 days)

**Gap Addressed**: GAP-002 (partial)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/streaming/event.ex`
- `/home/home/p/g/n/pristine/lib/pristine/streaming/sse_decoder.ex`

**Port From**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

**API**:
```elixir
defmodule Pristine.Streaming.Event do
  defstruct [:event, :data, :id, :retry]
  def json(%__MODULE__{data: data}), do: Jason.decode!(data)
end

defmodule Pristine.Streaming.SSEDecoder do
  defstruct buffer: ""
  def new(), do: %__MODULE__{}
  def feed(%__MODULE__{} = decoder, chunk), do: {events, new_decoder}
end
```

### 2.2 Streaming Transport (2-3 days)

**Gap Addressed**: GAP-002 (partial)

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/stream_transport.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/stream_response.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch_stream.ex`

**API**:
```elixir
defmodule Pristine.Ports.StreamTransport do
  @callback stream(Request.t(), Context.t()) :: {:ok, StreamResponse.t()} | {:error, term()}
end

defmodule Pristine.Core.StreamResponse do
  defstruct [:stream, :status, :headers, :metadata]
  @type t :: %__MODULE__{stream: Enumerable.t(), ...}
end
```

### 2.3 Pipeline Streaming Integration (1-2 days)

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`
- `/home/home/p/g/n/pristine/lib/pristine/core/context.ex`

**API**:
```elixir
Pipeline.execute_stream(manifest, endpoint_id, payload, context, opts)
# Returns {:ok, Enumerable.t()} of parsed events
```

### 2.4 Future/Polling Port (3 days)

**Gap Addressed**: GAP-003

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/future.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/future/polling.ex`

**Port From**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`

**API**:
```elixir
defmodule Pristine.Ports.Future do
  @callback poll(request_id :: String.t(), Context.t(), keyword()) :: {:ok, Task.t()}
  @callback await(Task.t(), timeout()) :: {:ok, term()} | {:error, term()}
end
```

---

## 5. Stage 3: Codegen Enhancement (5-7 days)

**Goal**: Generate SDK-quality code with full ergonomics.

### 3.1 Resource Module Grouping (2-3 days)

**Gap Addressed**: GAP-009

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex` (add `:resource` field)
- `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex`
- `/home/home/p/g/n/pristine/lib/pristine/codegen.ex`

**Generated Structure**:
```
lib/myapi/
├── client.ex           # Main client with resource accessors
├── models.ex           # client.models.* functions
├── sampling.ex         # client.sampling.* functions
└── types/
    ├── sample_request.ex
    └── ...
```

### 3.2 Client with Resource Accessors (1-2 days)

**Generated Code**:
```elixir
defmodule MyAPI.Client do
  defstruct [:context]

  def new(opts \\ []), do: %__MODULE__{context: Context.build(opts)}

  def models(%__MODULE__{} = client), do: MyAPI.Models.with_client(client)
  def sampling(%__MODULE__{} = client), do: MyAPI.Sampling.with_client(client)
end
```

### 3.3 Type Module Generation (2 days)

**Generated Code**:
```elixir
defmodule MyAPI.Types.SampleRequest do
  @moduledoc "Request type for sampling endpoint"

  defstruct [:prompt, :num_samples, :sampling_params]

  @type t :: %__MODULE__{...}

  def schema do
    Sinter.Schema.define([...])
  end

  def from_map(data), do: struct(__MODULE__, data)
  def to_map(%__MODULE__{} = s), do: Map.from_struct(s)
end
```

---

## 6. Stage 4: Resilience Completion (4-6 days)

**Goal**: Complete retry, rate limiting, and telemetry features.

### 4.1 Retry-After Header Parsing (1 day)

**Gap Addressed**: GAP-011

**Files to Create**:
- `/home/home/p/g/n/foundation/lib/foundation/retry/http.ex`

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/adapters/retry/foundation.ex`

### 4.2 Connection Limiting (2 days)

**Gap Addressed**: GAP-012

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/semaphore.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/semaphore/counting.ex`

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex`

### 4.3 Enhanced Telemetry Port (1-2 days)

**Gap Addressed**: GAP-020

**Files to Modify**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/telemetry.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/telemetry/foundation.ex`

**New Callbacks**:
```elixir
@callback measure(atom(), map(), (-> result)) :: result
@callback emit_counter(atom(), map()) :: :ok
@callback emit_gauge(atom(), number(), map()) :: :ok
```

### 4.4 Error Module (1 day)

**Gap Addressed**: GAP-018

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/error.ex`

---

## 7. Stage 5: Developer Tooling (5-8 days)

**Goal**: Complete developer experience with validation, docs, and testing.

### 5.1 OpenAPI Generation (2-3 days)

**Gap Addressed**: GAP-014

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/openapi.ex`
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.openapi.ex`

**API**:
```elixir
Pristine.OpenAPI.generate(manifest, opts)
# Returns OpenAPI 3.1 spec as map
```

### 5.2 Documentation Generation (2 days)

**Gap Addressed**: GAP-023

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/docs.ex`
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.docs.ex`

### 5.3 Test Fixtures Module (1 day)

**Gap Addressed**: GAP-024

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/test/fixtures.ex`

### 5.4 Mock Server Generation (2 days)

**Gap Addressed**: GAP-025

**Files to Create**:
- `/home/home/p/g/n/pristine/lib/pristine/test/mock_server.ex`

---

## 8. Stage 6: Integration & Polish (5-7 days)

**Goal**: End-to-end integration, testing, and documentation.

### 6.1 Tinkex Manifest Creation (2 days)

Create complete manifest for Tinkex:
- `/home/home/p/g/n/pristine/examples/tinkex/manifest.json`

### 6.2 Generate Tinkex from Manifest (1 day)

Verify full generation:
```bash
mix pristine.generate \
  --manifest examples/tinkex/manifest.json \
  --output examples/tinkex/generated
```

### 6.3 Integration Tests (2 days)

- Test generated client against mock server
- Verify streaming works end-to-end
- Verify future polling works

### 6.4 Documentation (1 day)

- Update README
- Add examples
- Document manifest schema

---

## 9. Dependency Graph

```
Stage 0 (Quick Wins)
    │
    ├──────────────────┬──────────────────┐
    │                  │                  │
    v                  v                  v
Stage 1            Stage 2            Stage 4
(Type System)      (Streaming)        (Resilience)
    │                  │                  │
    └──────────────────┼──────────────────┘
                       │
                       v
                  Stage 3
                  (Codegen)
                       │
                       v
                  Stage 5
                  (Tooling)
                       │
                       v
                  Stage 6
                  (Integration)
```

---

## 10. Risk Mitigation

### 10.1 Breaking Changes in Sinter

**Risk**: Discriminated unions, aliases could break existing usage.

**Mitigation**:
- Feature flag for new behavior
- Maintain backward compatibility
- Comprehensive test suite before changes

### 10.2 Streaming Complexity

**Risk**: SSE/streaming is complex new subsystem.

**Mitigation**:
- Port from tested Tinkex implementation
- Extensive unit tests
- Integration tests with real endpoints

### 10.3 Codegen Restructure

**Risk**: Resource grouping changes generated output significantly.

**Mitigation**:
- Optional via manifest setting
- Incremental rollout
- Maintain single-module option

---

## 11. Success Criteria

### 11.1 Stage Completion Criteria

| Stage | Criteria |
|-------|----------|
| 0 | All quick wins pass tests, mix pristine.validate works |
| 1 | All Tinker types can be expressed in Sinter |
| 2 | SSE streaming works end-to-end, futures poll correctly |
| 3 | Generated code matches Tinker SDK ergonomics |
| 4 | Retry respects headers, rate limiting works |
| 5 | Developers have full tooling suite |
| 6 | Tinkex generates from manifest, passes all tests |

### 11.2 Final Success Criteria

1. **Complete manifest** for Tinkex with all endpoints and types
2. **Pristine generates** Tinkex client from manifest
3. **Generated client** passes existing Tinkex test suite
4. **Streaming works** with SSE endpoints
5. **Future polling** works with async endpoints
6. **Developer tooling** (validate, docs, openapi) works
7. **Documentation** is complete

---

## 12. Resource Allocation Suggestion

### Parallel Workstreams

| Workstream | Stages | Owner Skill |
|------------|--------|-------------|
| Type System | 1.1, 1.2, 1.3, 1.4 | Schema/validation expert |
| Streaming | 2.1, 2.2, 2.3, 2.4 | HTTP/async expert |
| Codegen | 3.1, 3.2, 3.3 | Metaprogramming expert |
| Resilience | 4.1, 4.2, 4.3, 4.4 | Foundation maintainer |
| Tooling | 5.1, 5.2, 5.3, 5.4 | DX/CLI expert |

### Sequential Dependencies

1. Stage 0 must complete first (foundation for all)
2. Stage 1 and 2 can run in parallel
3. Stage 3 depends on Stage 1
4. Stage 4 can run in parallel with 2/3
5. Stage 5 depends on 1-3
6. Stage 6 is final integration

---

## 13. Appendix: File Changes Summary

### New Files (26)

| Path | Purpose |
|------|---------|
| `pristine/lib/pristine/streaming/event.ex` | SSE event struct |
| `pristine/lib/pristine/streaming/sse_decoder.ex` | SSE decoder |
| `pristine/lib/pristine/ports/stream_transport.ex` | Streaming port |
| `pristine/lib/pristine/core/stream_response.ex` | Stream response |
| `pristine/lib/pristine/adapters/transport/finch_stream.ex` | Finch streaming |
| `pristine/lib/pristine/ports/future.ex` | Future port |
| `pristine/lib/pristine/adapters/future/polling.ex` | Polling adapter |
| `pristine/lib/pristine/ports/semaphore.ex` | Semaphore port |
| `pristine/lib/pristine/adapters/semaphore/counting.ex` | Counting adapter |
| `pristine/lib/pristine/error.ex` | Error types |
| `pristine/lib/pristine/openapi.ex` | OpenAPI generation |
| `pristine/lib/pristine/docs.ex` | Doc generation |
| `pristine/lib/pristine/test/fixtures.ex` | Test fixtures |
| `pristine/lib/pristine/test/mock_server.ex` | Mock server |
| `pristine/lib/mix/tasks/pristine.validate.ex` | Validate task |
| `pristine/lib/mix/tasks/pristine.openapi.ex` | OpenAPI task |
| `pristine/lib/mix/tasks/pristine.docs.ex` | Docs task |
| `pristine/.credo.exs` | Credo config |
| `foundation/lib/foundation/retry/http.ex` | HTTP retry helpers |
| `sinter/lib/sinter/validation.ex` | Validation helpers (optional) |

### Modified Files (15)

| Path | Changes |
|------|---------|
| `pristine/lib/pristine/codegen/elixir.ex` | Docs, specs, resources |
| `pristine/lib/pristine/codegen.ex` | Resource grouping |
| `pristine/lib/pristine/manifest/endpoint.ex` | New fields |
| `pristine/lib/pristine/core/context.ex` | New config |
| `pristine/lib/pristine/core/pipeline.ex` | Streaming, semaphore |
| `pristine/lib/pristine/ports/telemetry.ex` | New callbacks |
| `pristine/lib/pristine/adapters/telemetry/foundation.ex` | Implement callbacks |
| `pristine/lib/pristine/adapters/multipart/ex.ex` | Expose features |
| `pristine/lib/pristine/ports/multipart.ex` | New callbacks |
| `pristine/mix.exs` | New deps |
| `sinter/lib/sinter/types.ex` | Discriminated, literal |
| `sinter/lib/sinter/schema.ex` | Aliases, pre_validate |
| `sinter/lib/sinter/validator.ex` | Hooks, aliases |
| `sinter/lib/sinter/transform.ex` | Alias output |
| `sinter/lib/sinter/json_schema.ex` | Discriminator |

---

## 14. Conclusion

This roadmap provides a comprehensive path from Pristine's current state to full Tinker SDK parity. The staged approach allows for:

1. **Quick wins** that improve developer experience immediately
2. **Parallel workstreams** for efficient resource utilization
3. **Clear dependencies** to avoid blockers
4. **Incremental delivery** with testable milestones
5. **Risk mitigation** through careful planning

Following this roadmap, Pristine will be capable of generating complete, production-quality API clients from declarative manifests, fully matching the ergonomics and capabilities of the original Tinker Python SDK.
