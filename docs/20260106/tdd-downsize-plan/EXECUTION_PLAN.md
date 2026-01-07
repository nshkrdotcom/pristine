# TDD Execution Plan: Downsize examples/tinkex

**Date**: 2026-01-06
**Goal**: Reduce examples/tinkex from 22,357 lines to ~5,000 lines while maintaining 100% feature parity
**Method**: Test-Driven Development with validation gates

---

## Current State

| Metric | Value |
|--------|-------|
| Source files (lib/) | 173 |
| Source lines | 22,357 |
| Test files | 107 |
| Test lines | 7,616 |
| Total tests | 1,702 |
| Failing tests (seed 0) | 8 |

## Target State

| Metric | Target |
|--------|--------|
| Source files (lib/) | ~50-60 |
| Source lines | ~5,000 |
| Test files | ~40-50 |
| Test lines | ~4,000 |
| Total tests | 1,702+ |
| Failing tests | 0 |

---

## Validation Gates (Must Pass Before Each Phase)

```bash
# Gate 1: All tests pass
cd /home/home/p/g/n/pristine/examples/tinkex && mix test --seed 0
cd /home/home/p/g/n/pristine/examples/tinkex && mix test --seed 12345
cd /home/home/p/g/n/pristine/examples/tinkex && mix test

# Gate 2: No dialyzer errors
cd /home/home/p/g/n/pristine/examples/tinkex && mix dialyzer

# Gate 3: No credo issues
cd /home/home/p/g/n/pristine/examples/tinkex && mix credo --strict

# Gate 4: No compilation warnings
cd /home/home/p/g/n/pristine/examples/tinkex && mix compile --warnings-as-errors

# Gate 5: Format check
cd /home/home/p/g/n/pristine/examples/tinkex && mix format --check-formatted
```

---

## Phase 0: Fix Test Isolation (BLOCKING)

**Problem**: 8 tests fail with seed 0 due to `persistent_term` state pollution.

**Files to fix**:
- `test/tinkex/sampling_client_observability_test.exs`

**Action**:
1. Convert to use Supertester.ExUnitFoundation with `isolation: :full_isolation`
2. Replace `persistent_term` with test-scoped state
3. Add proper setup/teardown

**Validation**:
```bash
mix test --seed 0  # Must pass
mix test --seed 12345  # Must pass
```

---

## Phase 1: Extend Pristine with Missing Ports

Before we can replace tinkex modules with Pristine, Pristine needs these additions.

### 1.1 BytesSemaphore Port + Adapter

**Location**: `lib/pristine/ports/bytes_semaphore.ex`, `lib/pristine/adapters/bytes_semaphore/genserver.ex`

**Port Contract**:
```elixir
defmodule Pristine.Ports.BytesSemaphore do
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback acquire(server :: GenServer.server(), bytes :: pos_integer(), timeout :: timeout()) :: :ok | {:error, :timeout}
  @callback release(server :: GenServer.server(), bytes :: pos_integer()) :: :ok
  @callback available(server :: GenServer.server()) :: non_neg_integer()
end
```

**Tests First**:
```elixir
# test/pristine/ports/bytes_semaphore_test.exs
test "acquires and releases bytes" do
  {:ok, sem} = BytesSemaphore.start_link(budget: 1000)
  assert :ok = BytesSemaphore.acquire(sem, 500)
  assert BytesSemaphore.available(sem) == 500
  assert :ok = BytesSemaphore.release(sem, 500)
  assert BytesSemaphore.available(sem) == 1000
end

test "blocks when over budget" do
  {:ok, sem} = BytesSemaphore.start_link(budget: 100)
  assert :ok = BytesSemaphore.acquire(sem, 100)

  task = Task.async(fn -> BytesSemaphore.acquire(sem, 50, 100) end)
  assert {:error, :timeout} = Task.await(task)
end
```

### 1.2 Compression Port + Adapter

**Location**: `lib/pristine/ports/compression.ex`, `lib/pristine/adapters/compression/gzip.ex`

**Port Contract**:
```elixir
defmodule Pristine.Ports.Compression do
  @callback compress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback decompress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback content_encoding() :: String.t()
end
```

### 1.3 Extend Retry Adapter with Telemetry

**File**: `lib/pristine/adapters/retry/foundation.ex`

**Add telemetry events**:
- `[:pristine, :retry, :attempt, :start]`
- `[:pristine, :retry, :attempt, :stop]`
- `[:pristine, :retry, :attempt, :exception]`

### 1.4 Extend Future Port with Full Implementation

**File**: `lib/pristine/adapters/future/polling.ex`

**Add**:
- State machine (pending → completed/failed)
- Queue state observers
- Configurable backoff policies
- Telemetry integration

**Validation Gate**: Run Pristine tests
```bash
cd /home/home/p/g/n/pristine && mix test
cd /home/home/p/g/n/pristine && mix dialyzer
```

---

## Phase 2: Replace Direct Infrastructure (TDD)

Replace 4 tinkex modules with Pristine equivalents.

### 2.1 Replace Tinkex.Semaphore

**Before**: `lib/tinkex/semaphore.ex` (GenServer implementation)
**After**: Use `Pristine.Adapters.Semaphore.Counting`

**TDD Process**:
1. Write adapter test in Pristine
2. Implement adapter
3. Change tinkex imports to use Pristine
4. Delete tinkex module
5. Run tinkex tests

### 2.2 Replace Tinkex.Multipart.Encoder

**Before**: `lib/tinkex/multipart/encoder.ex`
**After**: Use `Pristine.Adapters.Multipart.Ex`

### 2.3 Replace Tinkex.Error (partial)

**Before**: `lib/tinkex/error.ex`
**After**: Wrap `Pristine.Error` with tinkex-specific category logic

### 2.4 Replace Tinkex.Streaming.SSEDecoder

**Note**: Tinkex already uses `Pristine.Streaming.SSEDecoder`!
**Action**: Verify no duplicate, remove if exists

**Validation Gate**:
```bash
cd /home/home/p/g/n/pristine/examples/tinkex && mix test --seed 0
cd /home/home/p/g/n/pristine/examples/tinkex && mix test --seed 12345
```

---

## Phase 3: Wire HTTP to Pristine Pipeline

Replace tinkex's custom HTTP layer with Pristine's pipeline.

### 3.1 Create Tinkex Context Builder

```elixir
# lib/tinkex/pristine_context.ex
defmodule Tinkex.PristineContext do
  def build(config) do
    Pristine.Core.Context.new(
      transport: Pristine.Adapters.Transport.Finch,
      serializer: Pristine.Adapters.Serializer.JSON,
      retry: Pristine.Adapters.Retry.Foundation,
      auth: Pristine.Adapters.Auth.Bearer.new(config.api_key),
      telemetry: Pristine.Adapters.Telemetry.Foundation,
      config: %{
        base_url: config.base_url,
        timeout: config.timeout,
        pool: config.http_pool
      }
    )
  end
end
```

### 3.2 Replace API Request/Response Modules

**Before**:
- `lib/tinkex/api/request.ex` - Manual request building
- `lib/tinkex/api/response.ex` - Manual response parsing
- `lib/tinkex/api/response_handler.ex` - Error handling

**After**:
- Use `Pristine.Core.Pipeline.execute/5`
- Use `Pristine.Core.Request` and `Pristine.Core.Response`
- Use `Pristine.Error` for error classification

### 3.3 Replace Individual API Modules

Convert each API module to use Pristine pipeline:

```elixir
# Before (lib/tinkex/api/service.ex)
defmodule Tinkex.API.Service do
  def get_capabilities(config) do
    request = Request.build(:get, "/capabilities", config)
    Response.handle(HTTPClient.request(request))
  end
end

# After
defmodule Tinkex.API.Service do
  def get_capabilities(config) do
    context = Tinkex.PristineContext.build(config)
    Pristine.Runtime.execute(context, :get_capabilities, %{})
  end
end
```

**Validation Gate**: Each API module converted, tests pass

---

## Phase 4: Create Tinkex Manifest

### 4.1 Define Complete API Surface

```json
{
  "name": "tinkex",
  "version": "1.0.0",
  "base_url": "https://api.tinker.ai/v1",
  "auth": { "type": "bearer" },
  "endpoints": [
    {
      "name": "get_capabilities",
      "resource": "service",
      "method": "GET",
      "path": "/capabilities",
      "response_type": "ServerCapabilities"
    },
    {
      "name": "create_session",
      "resource": "session",
      "method": "POST",
      "path": "/sessions",
      "request_type": "CreateSessionRequest",
      "response_type": "Session"
    },
    {
      "name": "forward_backward",
      "resource": "training",
      "method": "POST",
      "path": "/training/forward-backward",
      "request_type": "ForwardBackwardRequest",
      "response_type": "ForwardBackwardResponse",
      "async": true
    },
    {
      "name": "sample",
      "resource": "sampling",
      "method": "POST",
      "path": "/sampling/generate",
      "request_type": "SampleRequest",
      "response_type": "SampleResponse",
      "streaming": true
    }
    // ... all other endpoints
  ],
  "types": {
    "ServerCapabilities": { ... },
    "Session": { ... },
    "ForwardBackwardRequest": { ... },
    // ... all types
  }
}
```

### 4.2 Validate Manifest

```bash
mix pristine.validate priv/manifest.json
```

---

## Phase 5: Generate Types with Pristine Codegen

### 5.1 Generate Type Modules

```bash
mix pristine.generate priv/manifest.json --output lib/tinkex/generated
```

### 5.2 Wire Types to Generated Code

Replace 67 hand-written type modules with generated ones.

**Before**: `lib/tinkex/types/model.ex` (hand-written)
**After**: `lib/tinkex/generated/types/model.ex` (generated)

### 5.3 Keep Domain Types Separate

Some types are domain-specific and should remain hand-written:
- Regularizer types
- Recovery types
- Custom loss types

**Validation Gate**: All type tests pass with generated types

---

## Phase 6: Generate Resources with Pristine Codegen

### 6.1 Generate Resource Modules

Pristine codegen will create:
- `lib/tinkex/generated/resources/service.ex`
- `lib/tinkex/generated/resources/session.ex`
- `lib/tinkex/generated/resources/training.ex`
- `lib/tinkex/generated/resources/sampling.ex`
- `lib/tinkex/generated/resources/rest.ex`

### 6.2 Wire Clients to Generated Resources

```elixir
# lib/tinkex/service_client.ex (simplified)
defmodule Tinkex.ServiceClient do
  alias Tinkex.Generated.Resources.Service

  def get_capabilities(client) do
    Service.get_capabilities(client.context)
  end
end
```

---

## Phase 7: Remove Duplicated Infrastructure

### Files to Delete

**Infrastructure (replaced by Pristine)**:
- `lib/tinkex/api/request.ex`
- `lib/tinkex/api/response.ex`
- `lib/tinkex/api/response_handler.ex`
- `lib/tinkex/api/compression.ex`
- `lib/tinkex/api/headers.ex`
- `lib/tinkex/api/url.ex`
- `lib/tinkex/api/helpers.ex`
- `lib/tinkex/semaphore.ex`
- `lib/tinkex/multipart/encoder.ex`
- `lib/tinkex/multipart/form_serializer.ex`
- `lib/tinkex/http_client.ex`

**Types (replaced by generated)**:
- All 67 files in `lib/tinkex/types/` except domain-specific ones

### Files to Keep

**Domain Logic**:
- `lib/tinkex/regularizer.ex`
- `lib/tinkex/regularizers/*.ex`
- `lib/tinkex/recovery/*.ex`
- `lib/tinkex/training/custom_loss.ex`
- `lib/tinkex/session_manager.ex`

**Clients (simplified)**:
- `lib/tinkex/service_client.ex`
- `lib/tinkex/training_client.ex`
- `lib/tinkex/sampling_client.ex`
- `lib/tinkex/rest_client.ex`

**Configuration**:
- `lib/tinkex/config.ex`
- `lib/tinkex/pool_key.ex`

---

## Phase 8: Final Cleanup

### 8.1 Update CLAUDE.md

Update implementation status:
- [x] Phase 0: Fix test isolation
- [x] Phase 1: Extend Pristine ports
- [x] Phase 2: Replace direct infrastructure
- [x] Phase 3: Wire HTTP to Pristine
- [x] Phase 4: Create manifest
- [x] Phase 5: Generate types
- [x] Phase 6: Generate resources
- [x] Phase 7: Remove duplicates
- [x] Phase 8: Final cleanup

### 8.2 Final Validation

```bash
# All tests pass with any seed
cd /home/home/p/g/n/pristine/examples/tinkex
mix test --seed 0
mix test --seed 12345
mix test

# No dialyzer errors
mix dialyzer

# No credo issues
mix credo --strict

# No compilation warnings
mix compile --warnings-as-errors

# Format check
mix format --check-formatted

# Line count verification
find lib -name "*.ex" | xargs wc -l | tail -1
# Target: ~5,000 lines
```

---

## Success Criteria

| Criterion | Target |
|-----------|--------|
| Tests passing (all seeds) | 100% |
| Dialyzer errors | 0 |
| Credo issues | 0 |
| Compilation warnings | 0 |
| Source lines | ≤5,000 |
| Feature parity | 100% |

---

## Execution Order

1. **Phase 0** - Fix test isolation (BLOCKING)
2. **Phase 1** - Extend Pristine (can parallelize with Phase 0)
3. **Phase 2** - Replace direct infrastructure
4. **Phase 3** - Wire HTTP to Pristine
5. **Phase 4** - Create manifest
6. **Phase 5** - Generate types
7. **Phase 6** - Generate resources
8. **Phase 7** - Remove duplicates
9. **Phase 8** - Final cleanup

Each phase has a validation gate. Do not proceed until gate passes.
