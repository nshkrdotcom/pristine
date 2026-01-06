# Pristine + Tinkex Architecture

## Vision

**Pristine** is a manifest-driven, hexagonal SDK generator. It provides reusable infrastructure for building API SDKs while keeping domain logic separate via ports and adapters.

**Tinkex** is a thin wrapper SDK that uses Pristine's infrastructure, containing only Tinker-specific business logic and configuration.

## Dependency Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    examples/tinkex (Standalone Mix App)                  │
│                                                                          │
│  mix.exs:                                                                │
│    {:pristine, path: "../../"}                                           │
│                                                                          │
│  .gitignore (app-specific)                                               │
│  ├── _build/                                                             │
│  ├── deps/                                                               │
│  └── *.ez                                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ depends on
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         lib/pristine (Core Library)                      │
│                                                                          │
│  mix.exs dependencies (all local paths):                                 │
└─────────────────────────────────────────────────────────────────────────┘
         │               │                  │                    │
         ▼               ▼                  ▼                    ▼
┌─────────────┐  ┌─────────────┐   ┌──────────────┐   ┌───────────────────┐
│  foundation │  │   sinter    │   │ multipart_ex │   │ telemetry_reporter│
│  ~/p/g/n/   │  │  ~/p/g/n/   │   │   ~/p/g/n/   │   │     ~/p/g/n/      │
├─────────────┤  ├─────────────┤   ├──────────────┤   ├───────────────────┤
│ • Retry     │  │ • Schema    │   │ • Multipart  │   │ • Telemetry batch │
│ • Backoff   │  │   validation│   │   encoding   │   │ • Transport       │
│ • Circuit   │  │ • NOT manual│   │ • Form-data  │   │ • Event queue     │
│   breaker   │  │   schemas   │   │              │   │                   │
│ • Rate      │  │ • Uses JSON │   │              │   │                   │
│   limiting  │  │   Schema    │   │              │   │                   │
└─────────────┘  └─────────────┘   └──────────────┘   └───────────────────┘
```

## Project Structure

```
pristine/
├── lib/pristine/                    # Core SDK generator infrastructure
│   ├── core/                        # Pipeline, request, response, context
│   ├── ports/                       # Interface contracts
│   ├── adapters/                    # Implementations (finch, json, etc.)
│   ├── codegen/                     # Code generation pipeline
│   ├── streaming/                   # SSE support
│   └── manifest/                    # Manifest loading and validation
│
├── examples/
│   └── tinkex/                      # STANDALONE Mix application
│       ├── mix.exs                  # deps: [{:pristine, path: "../../"}]
│       ├── mix.lock                 # App-specific lockfile
│       ├── .gitignore               # App-specific ignores
│       ├── lib/tinkex/              # Thin wrapper modules
│       ├── test/tinkex/             # App tests
│       ├── priv/                    # Manifest and static assets
│       └── generated/               # Codegen output
│
└── docs/
    └── 20260106/                    # Current sprint docs
```

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          End-User Applications                           │
│   (CLI tools, Phoenix apps, Mix tasks, Scripts using Tinkex SDK)        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│            examples/tinkex - THIN WRAPPER (~500-1000 LOC)               │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Configuration + Codegen                          │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                   │ │
│  │  │  manifest/  │ │  config/    │ │  generated/ │                   │ │
│  │  │  api.json   │ │  runtime.exs│ │  types.ex   │                   │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘                   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Domain-Specific Logic                            │ │
│  │  ┌───────────────┐ ┌───────────────┐ ┌────────────────┐            │ │
│  │  │TrainingClient │ │SamplingClient │ │  RestClient    │            │ │
│  │  │(orchestration)│ │(streaming)    │ │  (CRUD facade) │            │ │
│  │  └───────────────┘ └───────────────┘ └────────────────┘            │ │
│  │  ┌───────────────┐ ┌───────────────┐                               │ │
│  │  │  Regularizers │ │  ML Types     │  (domain models only)         │ │
│  │  └───────────────┘ └───────────────┘                               │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ {:pristine, path: "../../"}
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    lib/pristine - CORE INFRASTRUCTURE                    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                      Core Pipeline                                  │ │
│  │  execute/5  │  execute_stream/5  │  execute_future/5               │ │
│  │  (sync)         (SSE events)         (async polling)               │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────┐    ┌──────────────────────────────────────┐ │
│  │         Ports          │    │              Adapters                 │ │
│  │ (Interface Contracts)  │    │         (Implementations)            │ │
│  ├────────────────────────┤    ├──────────────────────────────────────┤ │
│  │ Transport              │───▶│ Finch, FinchStream                   │ │
│  │ Retry                  │───▶│ Foundation.Retry                     │ │
│  │ CircuitBreaker         │───▶│ Foundation.CircuitBreaker            │ │
│  │ RateLimit              │───▶│ Foundation.RateLimiter               │ │
│  │ Semaphore              │───▶│ BytesSemaphore, CountingSemaphore    │ │
│  │ Telemetry              │───▶│ TelemetryReporter                    │ │
│  │ Auth                   │───▶│ Bearer, ApiKey, OAuth                │ │
│  │ Serializer             │───▶│ Jason + Sinter validation            │ │
│  │ Multipart              │───▶│ MultipartEx                          │ │
│  │ Future                 │───▶│ Polling, Combiner                    │ │
│  └────────────────────────┘    └──────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Manifest + Codegen                               │ │
│  │  • Manifest loading and validation                                  │ │
│  │  • Type module generation                                           │ │
│  │  • Resource/client generation                                       │ │
│  │  • Schema generation (via Sinter)                                   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                       Streaming                                     │ │
│  │  • SSE decoder                                                      │ │
│  │  • Event stream handling                                            │ │
│  │  • Backpressure management                                          │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Local path dependencies
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Foundation Libraries                               │
│                                                                          │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐            │
│  │   foundation    │ │     sinter      │ │  multipart_ex   │            │
│  │   ~/p/g/n/      │ │    ~/p/g/n/     │ │    ~/p/g/n/     │            │
│  ├─────────────────┤ ├─────────────────┤ ├─────────────────┤            │
│  │ Retry logic     │ │ Schema          │ │ RFC 2046        │            │
│  │ Backoff algos   │ │ validation via  │ │ multipart       │            │
│  │ Circuit breaker │ │ JSON Schema     │ │ encoding        │            │
│  │ Rate limiting   │ │ (NOT manual     │ │                 │            │
│  │ Timeout mgmt    │ │  type specs)    │ │                 │            │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘            │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                      telemetry_reporter                              ││
│  │                         ~/p/g/n/                                     ││
│  ├─────────────────────────────────────────────────────────────────────┤│
│  │ Event batching  │  Async transport  │  Queue management              ││
│  └─────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Pristine Core (lib/pristine/)

**Owns ALL generalizable SDK infrastructure.** Everything from the original tinkex that is not Tinker-specific MUST be implemented here.

| Component | Responsibility | Source Library |
|-----------|----------------|----------------|
| `Core.Pipeline` | Request execution with full resilience stack | - |
| `Core.Context` | Runtime configuration container | - |
| `Core.Request/Response` | Normalized HTTP primitives | - |
| `Ports.Transport` | HTTP client contract | finch |
| `Ports.Retry` | Retry with backoff contract | foundation |
| `Ports.CircuitBreaker` | Circuit breaker contract | foundation |
| `Ports.RateLimit` | Rate limiting contract | foundation |
| `Ports.Semaphore` | Concurrency limiting | foundation |
| `Ports.Telemetry` | Observability contract | telemetry_reporter |
| `Ports.Auth` | Authentication strategies | - |
| `Ports.Serializer` | JSON encoding/decoding with validation | sinter |
| `Ports.Multipart` | Form-data encoding | multipart_ex |
| `Ports.Future` | Async operation handling | - |
| `Manifest` | API definition loading and validation | - |
| `Streaming` | SSE decoding and event handling | - |
| `Codegen` | Type and resource module generation | - |

### Tinkex Domain (examples/tinkex/)

**Owns ONLY Tinker-specific logic.** This is a thin wrapper providing configuration and domain orchestration.

| Component | Responsibility |
|-----------|----------------|
| `Tinkex` | Main module, client initialization |
| `Tinkex.Config` | Environment and runtime configuration |
| `TrainingClient` | Forward/backward/optim loop orchestration |
| `SamplingClient` | LLM generation with streaming wrappers |
| `RestClient` | Checkpoint/session management facade |
| `Types.*` | ML data structures (ModelInput, TensorData, etc.) |
| `Regularizers.*` | Loss function modifiers (L1, L2, etc.) |

### What Goes Where

**Into Pristine (generalizable):**
- HTTP client abstraction
- Retry logic and backoff algorithms
- Circuit breaker state machine
- Rate limiting (token bucket, sliding window)
- Byte semaphores and concurrency control
- Telemetry emission and batching
- SSE decoding
- Multipart form encoding
- Future/async polling
- Request/response transformation
- Error normalization
- Timeout management

**Into Tinkex (domain-specific):**
- Tinker API manifest
- Training loop semantics
- ML type definitions
- Regularizer implementations
- Gradient tracking
- Custom loss functions
- Session management logic

## Key Design Principles

### 1. Standalone App with Path Dependency

```elixir
# examples/tinkex/mix.exs
defmodule Tinkex.MixProject do
  use Mix.Project

  def project do
    [
      app: :tinkex,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:pristine, path: "../../"},
      # NO other infrastructure deps - they come via pristine
    ]
  end
end
```

### 2. Tinkex Uses Pristine Context

Instead of building its own HTTP layer:

```elixir
# Target implementation
defmodule Tinkex.TrainingClient do
  def forward_backward(client, data, loss_fn, opts \\ []) do
    payload = build_forward_backward_request(data, loss_fn)

    Pristine.Core.Pipeline.execute_future(
      client.manifest,
      :forward_backward,
      payload,
      client.context,
      opts
    )
  end
end
```

### 3. Manifest-Driven Configuration

```elixir
# examples/tinkex/priv/manifest.json
{
  "name": "tinkex",
  "version": "0.1.0",
  "base_url": "https://tinker.thinkingmachines.dev",
  "auth": {
    "default": [{"type": "bearer", "env": "TINKER_API_KEY"}]
  },
  "endpoints": {
    "forward_backward": {
      "method": "POST",
      "path": "/v1/models/{model_id}/forward_backward",
      "async": true
    }
  }
}
```

### 4. Full Parity with Original Tinkex

ALL functionality from the original `~/p/g/North-Shore-AI/tinkex` MUST be implemented:
- Training operations (forward, backward, optim_step)
- Sampling operations (generate, stream)
- Session management
- Checkpoint operations
- Error handling semantics
- Telemetry events
- All ML types

The difference is WHERE it's implemented:
- Infrastructure → Pristine
- Domain logic → examples/tinkex

## Development Methodology

### TDD/RGR (Test-Driven Development / Red-Green-Refactor)

All development follows strict TDD:

1. **Red** - Write a failing test for the next piece of functionality
2. **Green** - Write minimal code to make the test pass
3. **Refactor** - Clean up while keeping tests green

### Workflow

```bash
# 1. Identify gap from original tinkex
# 2. Write test in examples/tinkex/test/ or test/
# 3. Run test (should fail)
mix test test/path/to_test.exs

# 4. Implement in appropriate layer
# 5. Run test (should pass)
# 6. Refactor if needed
# 7. Run full suite
mix test && mix dialyzer && mix credo --strict
```

## Size Targets

| Layer | Target LOC | Notes |
|-------|------------|-------|
| Pristine core | ~8,000 | All infrastructure from tinkex absorbed |
| Tinkex wrapper | ~500-1000 | Config + domain orchestration only |
| Foundation libs | (external) | Already implemented |
| **Total new code** | ~9,000 | Down from ~18,000 original |

## Relationship to Other Projects

```
ChzEx (optional)      ─── Configuration framework, CLI parsing
        │
        ▼ (if SDK needs CLI)
┌───────────────────────────────────────────────────┐
│                    Tinkex                          │
│              (thin domain layer)                   │
└───────────────────────────────────────────────────┘
        │
        ▼ {:pristine, path: "../../"}
┌───────────────────────────────────────────────────┐
│                   Pristine                         │
│            (SDK infrastructure)                    │
└───────────────────────────────────────────────────┘
        │
        ├─▶ foundation (retry, circuit breaker, rate limit)
        ├─▶ sinter (schema validation via JSON Schema)
        ├─▶ multipart_ex (form encoding)
        └─▶ telemetry_reporter (event batching)
```

## Testing Architecture

### Supertester Integration (MANDATORY)

**ALL tests in Pristine and Tinkex MUST use [supertester](../../supertester) for proper test isolation.** This is non-negotiable. Test ordering issues and flaky tests indicate architecture problems and must be fixed, never ignored.

### Core Principles

1. **Full Isolation**: Every test runs in complete isolation using `Supertester.ExUnitFoundation`
2. **Zero Sleep**: No `Process.sleep/1` - use deterministic synchronization patterns
3. **Async-Safe**: All tests run with `async: true` enabled
4. **Automatic Cleanup**: Supertester handles all resource lifecycle management
5. **OTP-Aware Assertions**: Use `assert_genserver_state/2`, `assert_all_children_alive/1`, etc.

### Test Module Pattern

```elixir
defmodule Pristine.SomeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  test "example" do
    {:ok, pid} = setup_isolated_genserver(MyServer)
    :ok = cast_and_sync(pid, :message)
    assert_genserver_state(pid, fn s -> s.ready end)
  end
end
```

### Dependency Configuration

Both Pristine and Tinkex must include supertester as a test dependency:

```elixir
defp deps do
  [
    {:supertester, path: "../supertester", only: :test}
  ]
end
```

### Test Categories

| Category | Location | Focus |
|----------|----------|-------|
| Unit | `test/pristine/` | Individual modules, mocked deps |
| Integration | `test/integration/` | Multi-module workflows |
| E2E | `examples/tinkex/test/` | Full SDK usage patterns |

All categories MUST use supertester isolation.

## Next Steps

1. Convert `examples/tinkex` to standalone Mix app
2. Implement missing Pristine ports/adapters from original tinkex
3. Migrate tinkex infrastructure into Pristine
4. Reduce tinkex to thin wrapper
5. Validate full parity with original tinkex

See companion documents:
- `CHECKLIST.md` - Implementation progress tracking
- `GAP_ANALYSIS.md` - Feature comparison with original tinkex
