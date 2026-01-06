# Implementation Plan: Pristine + Tinkex Unification

**Date**: 2026-01-06
**Goal**: Tinkex becomes a thin manifest-driven configuration over pristine infrastructure

---

## Overview

```
BEFORE (current broken state):
┌─────────────────────────────────────────────────────────┐
│ pristine (4,686 lines)   │  examples/tinkex (22,357)   │
│ - Good hexagonal core    │  - Barely uses pristine     │
│ - Unused by tinkex       │  - Handwritten everything   │
└─────────────────────────────────────────────────────────┘

AFTER (target state):
┌──────────────────────────────────────────────────────────┐
│ pristine (~8,000 lines)                                  │
│ - Hexagonal core (existing)                              │
│ - Extended ports (bytes semaphore, compression, etc.)    │
│ - Foundation/sinter/multipart adapters                   │
│ - All infrastructure for HTTP SDKs                       │
└──────────────────────────────────────────────────────────┘
                         ↓ generates
┌──────────────────────────────────────────────────────────┐
│ tinkex (~3,000-5,000 lines)                              │
│ - manifest.json (API definition)                         │
│ - Domain types (if not generated)                        │
│ - Domain-specific logic (regularizers, training flows)   │
│ - CLI (optional)                                         │
└──────────────────────────────────────────────────────────┘
```

---

## Phase 0: Cleanup Pristine (1 step)

### 0.1 Delete examples/tinkex

```bash
rm -rf examples/tinkex
```

This code is not using pristine properly - it's a port that duplicates infrastructure.

**Outcome**: Clean pristine with only the valuable core

---

## Phase 1: Extend Pristine Ports (4 new ports)

Tinkex needs infrastructure pristine doesn't currently provide.

### 1.1 BytesSemaphore Port

```elixir
# lib/pristine/ports/bytes_semaphore.ex
defmodule Pristine.Ports.BytesSemaphore do
  @callback acquire(budget :: pos_integer(), timeout :: timeout()) :: :ok | {:error, :timeout}
  @callback release(bytes :: pos_integer()) :: :ok
  @callback available() :: non_neg_integer()
end
```

**Adapter**: Foundation-based implementation using atomic counters

### 1.2 Compression Port

```elixir
# lib/pristine/ports/compression.ex
defmodule Pristine.Ports.Compression do
  @callback compress(binary(), opts :: keyword()) :: {:ok, binary()} | {:error, term()}
  @callback decompress(binary(), opts :: keyword()) :: {:ok, binary()} | {:error, term()}
end
```

**Adapters**: Gzip, Zstd (optional)

### 1.3 Session Port

```elixir
# lib/pristine/ports/session.ex
defmodule Pristine.Ports.Session do
  @callback start(config :: map()) :: {:ok, session_id()} | {:error, term()}
  @callback stop(session_id()) :: :ok
  @callback execute(session_id(), request :: map()) :: {:ok, response :: map()} | {:error, term()}
end
```

### 1.4 Environment Port

```elixir
# lib/pristine/ports/environment.ex
defmodule Pristine.Ports.Environment do
  @callback get(key :: String.t()) :: {:ok, String.t()} | {:error, :not_found}
  @callback get!(key :: String.t()) :: String.t()
  @callback get_with_default(key :: String.t(), default :: String.t()) :: String.t()
end
```

**Outcome**: Pristine can support all tinkex infrastructure needs

---

## Phase 2: Refactor Original Tinkex - Foundation Integration

Work in `~/p/g/North-Shore-AI/tinkex` - this is where the stable, tested tinkex lives.

### 2.1 Add Foundation Dependency

```elixir
# mix.exs
{:foundation, path: "../foundation"}
```

### 2.2 Replace Custom Retry with Foundation

**Before** (custom):
```elixir
defmodule Tinkex.Retry do
  def with_retry(fun, opts) do
    # 100+ lines of custom retry logic
  end
end
```

**After** (foundation):
```elixir
defmodule Tinkex.Retry do
  def with_retry(fun, opts) do
    Foundation.Retry.with_retry(fun, opts)
  end
end
```

### 2.3 Replace Custom Telemetry with Foundation

**Before**:
```elixir
defmodule Tinkex.Telemetry do
  def emit(event, measurements, metadata) do
    # Custom telemetry implementation
  end
end
```

**After**:
```elixir
defmodule Tinkex.Telemetry do
  def emit(event, measurements, metadata) do
    Foundation.Telemetry.emit([:tinkex | event], measurements, metadata)
  end
end
```

### 2.4 Replace Custom Rate Limiter with Foundation

Similar pattern - delegate to Foundation.RateLimiter

### 2.5 Add Sinter for Type Validation

```elixir
defmodule Tinkex.Types.Model do
  use Sinter.Schema

  schema do
    field :id, :string, required: true
    field :name, :string, required: true
    field :status, :enum, values: [:active, :archived]
    # ...
  end
end
```

### 2.6 Validation Gate

```bash
cd ~/p/g/North-Shore-AI/tinkex
mix test --seed 0
mix test --seed 12345
mix test
```

**All tests must pass before proceeding.**

---

## Phase 3: Refactor Original Tinkex - Hexagonal

### 3.1 Define Tinkex Ports

```elixir
# lib/tinkex/ports/http_client.ex
defmodule Tinkex.Ports.HTTPClient do
  @callback request(method, url, headers, body, opts) :: {:ok, response} | {:error, term()}
  @callback stream(method, url, headers, body, opts) :: {:ok, stream} | {:error, term()}
end
```

### 3.2 Create Adapter Modules

```elixir
# lib/tinkex/adapters/http_client/finch.ex
defmodule Tinkex.Adapters.HTTPClient.Finch do
  @behaviour Tinkex.Ports.HTTPClient

  def request(method, url, headers, body, opts) do
    Finch.build(method, url, headers, body)
    |> Finch.request(opts[:pool])
  end
end
```

### 3.3 Inject Adapters via Config

```elixir
# lib/tinkex/config.ex
defmodule Tinkex.Config do
  defstruct [
    http_client: Tinkex.Adapters.HTTPClient.Finch,
    serializer: Tinkex.Adapters.Serializer.JSON,
    retry: Tinkex.Adapters.Retry.Foundation,
    # ...
  ]
end
```

### 3.4 Validation Gate

```bash
mix test --seed 0
mix test --seed 12345
```

**All tests must pass before proceeding.**

---

## Phase 4: Create Tinkex Manifest

### 4.1 Define Full API Surface

```json
{
  "name": "tinkex",
  "version": "1.0.0",
  "base_url": "https://api.tinker.ai/v1",
  "auth": {
    "type": "bearer",
    "header": "Authorization"
  },
  "endpoints": [
    {
      "name": "create_model",
      "resource": "models",
      "method": "POST",
      "path": "/models",
      "request_type": "CreateModelRequest",
      "response_type": "Model",
      "retry": { "max_attempts": 3, "backoff": "exponential" }
    },
    {
      "name": "get_model",
      "resource": "models",
      "method": "GET",
      "path": "/models/{model_id}",
      "response_type": "Model"
    },
    {
      "name": "create_sample",
      "resource": "sampling",
      "method": "POST",
      "path": "/sampling/generate",
      "request_type": "SampleRequest",
      "response_type": "SampleResponse",
      "streaming": true,
      "rate_limit": { "requests_per_second": 10 }
    }
    // ... all other endpoints
  ],
  "types": {
    "Model": {
      "kind": "object",
      "fields": {
        "id": { "type": "string", "required": true },
        "name": { "type": "string", "required": true },
        "status": { "type": "enum", "values": ["active", "archived"] }
      }
    }
    // ... all other types
  }
}
```

### 4.2 Validate Manifest Against Pristine

```bash
mix pristine.validate priv/manifest.json
```

---

## Phase 5: Integrate Pristine into Tinkex

### 5.1 Add Pristine Dependency

```elixir
# mix.exs
{:pristine, path: "../pristine"}
```

### 5.2 Generate SDK Code

```bash
mix pristine.generate priv/manifest.json --output lib/tinkex/generated
```

### 5.3 Wire Tinkex to Use Generated Code

```elixir
# lib/tinkex.ex
defmodule Tinkex do
  alias Tinkex.Generated.Client

  def new(opts) do
    context = Pristine.Core.Context.new(
      transport: Pristine.Adapters.Transport.Finch,
      serializer: Pristine.Adapters.Serializer.JSON,
      retry: Pristine.Adapters.Retry.Foundation,
      auth: Pristine.Adapters.Auth.Bearer.new(opts[:api_key])
    )

    Client.new(context)
  end

  defdelegate models(client), to: Client
  defdelegate sampling(client), to: Client
end
```

### 5.4 Replace Hand-Written API Modules

**Before** (handwritten):
```elixir
defmodule Tinkex.API.Models do
  def create(client, params) do
    # 50+ lines of manual request building
  end
end
```

**After** (generated):
```elixir
# lib/tinkex/generated/resources/models.ex (auto-generated)
defmodule Tinkex.Generated.Resources.Models do
  def create(%{context: context}, params) do
    Pristine.Runtime.execute(context, :create_model, params)
  end
end
```

### 5.5 Keep Domain-Specific Logic Separate

```elixir
# lib/tinkex/domain/regularizers.ex
defmodule Tinkex.Domain.Regularizers do
  # This is domain logic, NOT infrastructure
  # Keep it in tinkex, don't try to generalize

  def apply_regularization(model, data, opts) do
    # Business logic specific to ML training
  end
end
```

### 5.6 Validation Gate

```bash
mix test --seed 0
mix test --seed 12345
```

---

## Phase 6: Cleanup Tinkex

### 6.1 Remove Duplicated Infrastructure

Delete these modules (now provided by pristine):
- `lib/tinkex/http_client.ex` → use Pristine.Adapters.Transport.Finch
- `lib/tinkex/retry.ex` → use Pristine.Adapters.Retry.Foundation
- `lib/tinkex/telemetry.ex` → use Pristine.Adapters.Telemetry.Foundation
- `lib/tinkex/serializer.ex` → use Pristine.Adapters.Serializer.JSON
- `lib/tinkex/rate_limiter.ex` → use pristine port

### 6.2 Final Structure

```
tinkex/
├── lib/
│   ├── tinkex.ex              # Entry point (thin)
│   ├── tinkex/
│   │   ├── config.ex          # Configuration
│   │   ├── generated/         # Pristine-generated code
│   │   │   ├── client.ex
│   │   │   ├── resources/
│   │   │   └── types/
│   │   └── domain/            # Business logic only
│   │       ├── regularizers.ex
│   │       ├── training_flows.ex
│   │       └── recovery.ex
├── priv/
│   └── manifest.json          # API definition
└── test/
```

### 6.3 Line Count Target

| Before | After | Component |
|--------|-------|-----------|
| 22,000+ | ~1,000 | Hand-written lib/ |
| 0 | ~3,000 | Generated code |
| N/A | ~500 | Domain logic |
| **22,000+** | **~4,500** | **Total** |

---

## Success Criteria

1. **Tinkex tests pass** with pristine as dependency
2. **Generated code** handles 90%+ of API surface
3. **Hand-written code** is domain logic only
4. **No infrastructure duplication** between tinkex and pristine
5. **Manifest** is source of truth for API definition
6. **Adding new endpoint** = add to manifest + regenerate

---

## Risk Mitigation

### Risk: Breaking Changes During Migration
**Mitigation**: Each phase has validation gate (tests must pass)

### Risk: Missing Features in Pristine
**Mitigation**: Phase 1 extends pristine before migration begins

### Risk: Generated Code Doesn't Match Needs
**Mitigation**: Keep domain logic separate, only generate infrastructure

### Risk: Performance Regression
**Mitigation**: Benchmark critical paths before/after each phase
