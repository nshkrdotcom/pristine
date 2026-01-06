# Delineation: What Goes Where

This document specifies the exact placement of every component from the original tinkex monolith, with explicit mapping to Pristine's local dependencies.

## Local Dependencies

Pristine uses these local dependencies for core infrastructure:

| Dependency | Purpose | Pristine Integration |
|------------|---------|---------------------|
| `foundation` | Retry, circuit breaker, rate limiting, backoff | `Pristine.Adapters.Retry.Foundation`, `Pristine.Adapters.CircuitBreaker.Foundation`, `Pristine.Adapters.RateLimit.BackoffWindow` |
| `sinter` | ALL schema validation (request/response types) | `Pristine.Adapters.Serializer.JSON` (validates via Sinter schemas) |
| `multipart_ex` | Multipart/form-data encoding | `Pristine.Adapters.Multipart.Ex` |
| `telemetry_reporter` | Telemetry batching and transport | `Pristine.Adapters.Telemetry.Reporter` |

**CRITICAL**: `examples/tinkex` is a standalone Mix application and MUST NOT duplicate ANY functionality provided by these dependencies or Pristine itself.

---

## Summary

| Category | Pristine | Tinkex | Delete | Notes |
|----------|----------|--------|--------|-------|
| HTTP/Transport | 100% | 0% | - | Via Finch adapter |
| Retry/Resilience | 100% | 0% | - | Via foundation |
| Schema Validation | 100% | 0% | - | Via sinter |
| Telemetry | 100% | 0% | - | Via telemetry_reporter |
| Streaming | 100% | 0% | - | SSEDecoder in Pristine |
| Session/Future | 100% | 0% | - | Via Pristine Core |
| Multipart | 100% | 0% | - | Via multipart_ex |
| Domain Clients | 0% | 100% | - | Thin wrappers only |
| ML Types | 0% | 100% | - | Domain-specific |
| Regularizers | 0% | 100% | - | ML-specific |
| Recovery | 0% | 100% | - | Training-specific |
| CLI | 0% | 100% (opt) | - | Optional escript |
| HuggingFace | 0% | 100% | - | External integration |

---

## Module Placement by Dependency

### Uses `foundation`

These modules use foundation for retry, circuit breaker, and rate limiting:

| Original Tinkex | Pristine Location | foundation Usage |
|-----------------|-------------------|------------------|
| `Tinkex.Retry` | `Pristine.Ports.Retry` | Port definition |
| `Tinkex.RetryHandler` | `Pristine.Adapters.Retry.Foundation` | Uses `Foundation.Retry` |
| `Tinkex.RetryConfig` | `Pristine.Core.Context` | Config in context, validated by foundation |
| `Tinkex.API.Retry` | Delete | Redundant - use foundation adapter |
| `Tinkex.API.RetryConfig` | Delete | Redundant - use foundation config |
| `Tinkex.CircuitBreaker` | `Pristine.Ports.CircuitBreaker` | Port definition |
| `Tinkex.CircuitBreaker.Registry` | `Pristine.Adapters.CircuitBreaker.Foundation` | Uses `Foundation.CircuitBreaker` |
| `Tinkex.RateLimiter` | `Pristine.Ports.RateLimit` | Port definition |
| `Tinkex.BytesSemaphore` | `Pristine.Adapters.Semaphore.Bytes` | Uses foundation backoff patterns |
| `Tinkex.Semaphore` | `Pristine.Ports.Semaphore` | Port definition |
| `Tinkex.RetrySemaphore` | `Pristine.Adapters.Semaphore.Retry` | Uses foundation retry |
| `Tinkex.PoolKey` | `Pristine.Core.PoolKey` | Foundation connection pool key |

### Uses `sinter`

These modules use sinter for schema validation (replaces ALL manual type validation):

| Original Tinkex | Pristine Location | sinter Usage |
|-----------------|-------------------|--------------|
| `Tinkex.Types.*` (request types) | Manifest type definitions | Sinter schema validation on requests |
| `Tinkex.Types.*` (response types) | Manifest type definitions | Sinter schema validation on responses |
| Manual `validate/1` functions | Delete | Replaced by Sinter schema validation |
| `Tinkex.API.Request` | `Pristine.Core.Request` | Sinter validates request body |
| `Tinkex.API.Response` | `Pristine.Core.Response` | Sinter validates response body |
| Type coercion logic | `Pristine.Adapters.Serializer.JSON` | Sinter handles type coercion |

**Tinkex Types Stay Domain-Specific**:
ML types (ModelInput, TensorData, Datum, etc.) remain in Tinkex but validation is delegated to Sinter schemas defined in the manifest.

### Uses `multipart_ex`

These modules use multipart_ex for form encoding:

| Original Tinkex | Pristine Location | multipart_ex Usage |
|-----------------|-------------------|-------------------|
| `Tinkex.Multipart.Encoder` | `Pristine.Adapters.Multipart.Ex` | Direct `MultipartEx` usage |
| `Tinkex.Multipart.FormSerializer` | `Pristine.Adapters.Multipart.FormSerializer` | Uses `MultipartEx.encode/1` |
| `Tinkex.Files.Types` | `Pristine.Core.Files.Types` | File metadata for multipart |

### Uses `telemetry_reporter`

These modules use telemetry_reporter for batching and transport:

| Original Tinkex | Pristine Location | telemetry_reporter Usage |
|-----------------|-------------------|-------------------------|
| `Tinkex.Telemetry` | `Pristine.Ports.Telemetry` | Port definition |
| `Tinkex.Telemetry.Capture` | `Pristine.Core.Telemetry.Capture` | Event capture macros |
| `Tinkex.Telemetry.Provider` | `Pristine.Adapters.Telemetry.Provider` | Provider abstraction |
| `Tinkex.Telemetry.Otel` | `Pristine.Adapters.Telemetry.Otel` | OTEL context propagation |
| `Tinkex.Telemetry.Reporter` | `Pristine.Adapters.Telemetry.Reporter` | Uses `TelemetryReporter` |
| `Tinkex.Telemetry.Reporter.Queue` | Delete | Provided by telemetry_reporter |
| `Tinkex.Telemetry.Reporter.Events` | Delete | Provided by telemetry_reporter |
| `Tinkex.Telemetry.Reporter.Backoff` | Delete | Uses foundation backoff |
| `Tinkex.Telemetry.Reporter.Serializer` | Delete | Provided by telemetry_reporter |
| `Tinkex.Telemetry.Reporter.ExceptionHandler` | Delete | Provided by telemetry_reporter |
| `Tinkex.API.Telemetry` | Delete | Use Pristine telemetry |

---

## Detailed Module Placement

### TO PRISTINE (Generalize)

These modules move to Pristine as generalized infrastructure:

#### HTTP/Transport Layer

| Original | Target | Notes |
|----------|--------|-------|
| `Tinkex.API` | `Pristine.Core.Pipeline` | Already exists, use it |
| `Tinkex.API.Request` | `Pristine.Core.Request` | Already exists |
| `Tinkex.API.Response` | `Pristine.Core.Response` | Already exists |
| `Tinkex.API.ResponseHandler` | `Pristine.Core.Pipeline` | Merge into pipeline |
| `Tinkex.API.StreamResponse` | `Pristine.Core.StreamResponse` | Already exists |
| `Tinkex.API.Headers` | `Pristine.Core.Headers` | Already exists |
| `Tinkex.API.URL` | `Pristine.Core.Url` | Already exists |
| `Tinkex.API.Compression` | `Pristine.Core.Compression` | **NEW** |
| `Tinkex.API.Helpers` | Delete | Inline utilities |
| `Tinkex.HTTPClient` | `Pristine.Ports.Transport` | Use port/adapter |

#### Streaming

| Original | Target | Notes |
|----------|--------|-------|
| `Tinkex.Streaming.SSEDecoder` | `Pristine.Streaming.SSEDecoder` | Already exists |
| `Tinkex.Streaming.ServerSentEvent` | `Pristine.Streaming.Event` | Already exists |

#### Session/Future Management

| Original | Target | Notes |
|----------|--------|-------|
| `Tinkex.Future` | `Pristine.Ports.Future` | Use existing port |
| `Tinkex.Future.Combiner` | `Pristine.Adapters.Future.Combiner` | **NEW** |
| `Tinkex.SessionManager` | `Pristine.Core.SessionManager` | **NEW** |
| `Tinkex.API.Session` | Via manifest endpoints | Define in manifest |
| `Tinkex.API.Futures` | `Pristine.Core.Pipeline.execute_future` | Already exists |

#### Files/Multipart

| Original | Target | Notes |
|----------|--------|-------|
| `Tinkex.Files.Reader` | `Pristine.Core.Files.Reader` | **NEW** |
| `Tinkex.Files.AsyncReader` | `Pristine.Core.Files.AsyncReader` | **NEW** |
| `Tinkex.Files.Transform` | `Pristine.Core.Files.Transform` | **NEW** |
| `Tinkex.Files.Types` | `Pristine.Core.Files.Types` | **NEW** |
| `Tinkex.Multipart.Encoder` | `Pristine.Adapters.Multipart.Ex` | Already exists (uses multipart_ex) |
| `Tinkex.Multipart.FormSerializer` | `Pristine.Adapters.Multipart.FormSerializer` | **NEW** (uses multipart_ex) |

#### Utilities

| Original | Target | Notes |
|----------|--------|-------|
| `Tinkex.Config` | Via `Pristine.Core.Context` | SDK uses context |
| `Tinkex.Error` | `Pristine.Error` | Already exists, enhance |
| `Tinkex.Env` | `Pristine.Core.Env` | **NEW** |
| `Tinkex.NotGiven` | `Pristine.Core.NotGiven` | **NEW** |
| `Tinkex.Transform` | `Pristine.Core.Transform` | **NEW** |
| `Tinkex.Logging` | `Pristine.Core.Logging` | **NEW** |
| `Tinkex.Version` | Delete | SDK provides own version |

---

### TO TINKEX (Domain-Specific)

These modules stay in Tinkex as domain logic. **They MUST NOT duplicate Pristine functionality.**

#### Domain Clients (Thin Wrappers)

| Module | Responsibility | Pristine Calls |
|--------|----------------|----------------|
| `Tinkex` | Main entrypoint, creates clients | - |
| `Tinkex.ServiceClient` | Session orchestration, client factory | `Pipeline.execute`, `Pipeline.execute_future` |
| `Tinkex.TrainingClient` | Forward/backward/optim loop | `Pipeline.execute_future` |
| `Tinkex.TrainingClient.DataProcessor` | Chunking, tensor ops | Pure domain logic |
| `Tinkex.TrainingClient.Observer` | Queue state debouncing | Pure domain logic |
| `Tinkex.TrainingClient.Operations` | Request building | Builds payloads for Pipeline |
| `Tinkex.TrainingClient.Polling` | Future result awaiting | Uses `Future.Combiner` |
| `Tinkex.TrainingClient.Tokenizer` | Tokenizer integration | May use Pristine tokenizer port |
| `Tinkex.SamplingClient` | Text generation, streaming | `Pipeline.execute_stream` |
| `Tinkex.SamplingDispatch` | Concurrent sampling dispatch | Uses Pristine semaphores |
| `Tinkex.SamplingRegistry` | Sampler registration | Pure domain logic |
| `Tinkex.RestClient` | Checkpoint/session facade | `Pipeline.execute` |

#### ML Types (Domain-Specific, Validated by Sinter)

All types stay in Tinkex but are validated by Sinter schemas:

```
Tinkex.Types.
├── ModelInput          # Token sequences + images (sinter-validated)
├── TensorData          # Nx tensor wrapper (sinter-validated)
├── TensorDtype         # int64, float32, etc. (sinter enum)
├── Datum               # Training example (sinter-validated)
├── AdamParams          # Optimizer hyperparameters (sinter-validated)
├── LossFnType          # cross_entropy, ppo, dro (sinter enum)
├── SamplingParams      # temperature, top_k, top_p (sinter-validated)
├── SampledSequence     # Generation result (sinter-validated)
├── SampleStreamChunk   # Streaming token (sinter-validated)
├── LoraConfig          # LoRA hyperparameters (sinter-validated)
├── Checkpoint          # Checkpoint metadata (sinter-validated)
├── QueueState          # Rate limit feedback (sinter-validated)
├── CustomLossOutput    # Custom loss result (sinter-validated)
├── RegularizerOutput   # Regularizer result (sinter-validated)
├── RegularizerSpec     # Regularizer config (sinter-validated)
└── [60+ more types]    # Request/response types (all sinter-validated)
```

#### Regularizers (Domain-Specific)

All regularizers stay in Tinkex (ML-specific, no infrastructure):

| Module | Description |
|--------|-------------|
| `Tinkex.Regularizer` | Behaviour definition |
| `Tinkex.Regularizer.Executor` | Parallel execution |
| `Tinkex.Regularizer.Pipeline` | Chained execution |
| `Tinkex.Regularizer.GradientTracker` | Gradient norm tracking |
| `Tinkex.Regularizer.Telemetry` | Regularizer metrics (emits to Pristine telemetry) |
| `Tinkex.Regularizers.L1` | L1 penalty |
| `Tinkex.Regularizers.L2` | L2 weight decay |
| `Tinkex.Regularizers.ElasticNet` | Combined L1+L2 |
| `Tinkex.Regularizers.Entropy` | Entropy regularization |
| `Tinkex.Regularizers.KLDivergence` | KL penalty |
| `Tinkex.Regularizers.Consistency` | DRO consistency |
| `Tinkex.Regularizers.GradientPenalty` | Gradient norm penalty |
| `Tinkex.Regularizers.Orthogonality` | Weight orthogonality |

#### Recovery (Domain-Specific)

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.Recovery.Policy` | Tinkex | Training-specific policies |
| `Tinkex.Recovery.Behaviours` | Tinkex | Callbacks for recovery |
| `Tinkex.Recovery.Executor` | Tinkex | Training recovery orchestration |
| `Tinkex.Recovery.Monitor` | Tinkex | Training run polling |

#### Streaming (Domain)

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.Streaming.SampleStream` | Tinkex | Uses `Pristine.Streaming.SSEDecoder` |

#### Observability (Domain)

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.Metrics` | Tinkex | Training metrics (emits to Pristine telemetry) |
| `Tinkex.MetricsReduction` | Tinkex | Metric aggregation |
| `Tinkex.QueueStateObserver` | Tinkex | Rate limit feedback |
| `Tinkex.QueueStateLogger` | Tinkex | Logging integration |
| `Tinkex.ByteEstimator` | Tinkex | Token->byte estimation |

#### Training

| Module | Location |
|--------|----------|
| `Tinkex.Training.CustomLoss` | Tinkex |

#### Tokenizer

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.Tokenizer` | Tinkex | Orchestration |
| `Tinkex.Tokenizer.HTTPClient` | Tinkex | HF tokenizer fetching |

#### External Integrations

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.HuggingFace` | Tinkex | HF file resolution |
| `Tinkex.CheckpointDownload` | Tinkex | Checkpoint fetching |

#### Application

| Module | Location |
|--------|----------|
| `Tinkex.Application` | Tinkex |

#### CLI (Optional)

The CLI is **optional** and stays in Tinkex. It provides an escript for command-line usage:

| Module | Location | Notes |
|--------|----------|-------|
| `Tinkex.CLI` | Tinkex (optional) | Main entrypoint |
| `Tinkex.CLI.Parser` | Tinkex (optional) | Argument parsing |
| `Tinkex.CLI.Pagination` | Tinkex (optional) | List pagination |
| `Tinkex.CLI.Formatting` | Tinkex (optional) | Output formatting |
| `Tinkex.CLI.Commands.Checkpoint` | Tinkex (optional) | Checkpoint save/list/delete |
| `Tinkex.CLI.Commands.Run` | Tinkex (optional) | Training run management |
| `Tinkex.CLI.Commands.Sample` | Tinkex (optional) | Text generation |
| `Tinkex.CLI.Commands.Version` | Tinkex (optional) | Version display |

**CLI Dependencies**: The CLI uses the domain clients (TrainingClient, SamplingClient, RestClient) which in turn use Pristine. The CLI itself has no infrastructure dependencies.

---

### TO DELETE

These modules are removed entirely (replaced by Pristine + dependencies):

| Module | Reason | Replaced By |
|--------|--------|-------------|
| `Tinkex.API.*` (15 modules) | HTTP infrastructure | `Pristine.Core.Pipeline` |
| `Tinkex.HTTPClient` | Transport | `Pristine.Adapters.Transport.Finch` |
| `Tinkex.Retry` | Retry logic | `Pristine.Adapters.Retry.Foundation` (uses foundation) |
| `Tinkex.RetryHandler` | Retry logic | `Pristine.Adapters.Retry.Foundation` (uses foundation) |
| `Tinkex.RetryConfig` | Retry config | `Pristine.Core.Context` (uses foundation) |
| `Tinkex.CircuitBreaker` | Circuit breaker | `Pristine.Adapters.CircuitBreaker.Foundation` (uses foundation) |
| `Tinkex.CircuitBreaker.Registry` | CB registry | `Pristine.Adapters.CircuitBreaker.Foundation` (uses foundation) |
| `Tinkex.RateLimiter` | Rate limiting | `Pristine.Adapters.RateLimit.BackoffWindow` (uses foundation) |
| `Tinkex.Semaphore` | Concurrency | `Pristine.Adapters.Semaphore.Counting` |
| `Tinkex.BytesSemaphore` | Byte budget | `Pristine.Adapters.Semaphore.Bytes` |
| `Tinkex.RetrySemaphore` | Retry sem | `Pristine.Adapters.Semaphore.Retry` |
| `Tinkex.PoolKey` | Pool key | `Pristine.Core.PoolKey` |
| `Tinkex.Telemetry.*` (10 modules) | Telemetry infra | `Pristine.Adapters.Telemetry.Reporter` (uses telemetry_reporter) |
| `Tinkex.Multipart.*` | Multipart | `Pristine.Adapters.Multipart.Ex` (uses multipart_ex) |
| `Tinkex.Files.*` | File handling | `Pristine.Core.Files.*` |
| `Tinkex.Future` | Future handling | `Pristine.Ports.Future` |
| `Tinkex.Future.Combiner` | Future combining | `Pristine.Adapters.Future.Combiner` |
| `Tinkex.SessionManager` | Session mgmt | `Pristine.Core.SessionManager` |
| `Tinkex.Config` | Configuration | `Pristine.Core.Context` |
| `Tinkex.Error` | Error types | `Pristine.Error` |
| `Tinkex.Env` | Env vars | `Pristine.Core.Env` |
| `Tinkex.NotGiven` | Sentinel | `Pristine.Core.NotGiven` |
| `Tinkex.Transform` | Transforms | `Pristine.Core.Transform` |
| `Tinkex.Logging` | Logging | `Pristine.Core.Logging` |
| `Tinkex.Version` | Version | Delete entirely |
| Manual type validation | Per-type | Sinter schema validation |

---

## API Endpoints via Manifest

Instead of `Tinkex.API.*` modules, endpoints are defined in manifest:

```elixir
# examples/tinkex/priv/manifest.exs
%{
  endpoints: %{
    # Session API
    create_session: %{method: :post, path: "/v1/sessions", ...},
    heartbeat: %{method: :post, path: "/v1/sessions/{session_id}/heartbeat", ...},

    # Service API
    create_model: %{method: :post, path: "/v1/models", async: true, ...},
    create_sampling_session: %{method: :post, path: "/v1/samplers", async: true, ...},
    get_server_capabilities: %{method: :get, path: "/v1/capabilities", ...},

    # Training API
    forward_backward: %{method: :post, path: "/v1/models/{model_id}/forward_backward", async: true, ...},
    forward: %{method: :post, path: "/v1/models/{model_id}/forward", async: true, ...},
    optim_step: %{method: :post, path: "/v1/models/{model_id}/optim_step", async: true, ...},
    save_weights: %{method: :post, path: "/v1/models/{model_id}/save", async: true, ...},
    load_weights: %{method: :post, path: "/v1/models/{model_id}/load", async: true, ...},

    # Sampling API
    sample: %{method: :post, path: "/v1/samplers/{sampler_id}/sample", async: true, ...},
    sample_stream: %{method: :post, path: "/v1/samplers/{sampler_id}/sample_stream", streaming: true, ...},
    compute_logprobs: %{method: :post, path: "/v1/samplers/{sampler_id}/logprobs", async: true, ...},

    # Weights API
    save_weights_for_sampler: %{method: :post, path: "/v1/weights/save_for_sampler", async: true, ...},

    # Future API
    retrieve_result: %{method: :post, path: "/v1/futures/retrieve", ...},

    # REST API
    list_sessions: %{method: :get, path: "/v1/sessions", ...},
    get_session: %{method: :get, path: "/v1/sessions/{session_id}", ...},
    list_checkpoints: %{method: :get, path: "/v1/checkpoints", ...},
    # ... etc
  },

  # Type schemas validated by Sinter
  types: %{
    ModelInput: %{
      type: :object,
      properties: %{
        tokens: %{type: :array, items: %{type: :integer}},
        images: %{type: :array, items: %{type: :binary}}
      }
    },
    # ... etc
  }
}
```

---

## File Structure After Migration

```
examples/tinkex/
├── lib/
│   └── tinkex/
│       ├── tinkex.ex                    # Entrypoint
│       ├── service_client.ex            # Session orchestration (uses Pristine.Core.Pipeline)
│       ├── training_client.ex           # Training loop (uses Pristine.Core.Pipeline)
│       ├── training_client/
│       │   ├── data_processor.ex        # Pure domain logic
│       │   ├── observer.ex              # Pure domain logic
│       │   ├── operations.ex            # Builds payloads for Pipeline
│       │   ├── polling.ex               # Uses Pristine.Adapters.Future.Combiner
│       │   └── tokenizer.ex             # Domain + may use Pristine tokenizer
│       ├── sampling_client.ex           # Text generation (uses Pristine.Core.Pipeline)
│       ├── sampling_dispatch.ex         # Uses Pristine semaphores
│       ├── sampling_registry.ex         # Pure domain logic
│       ├── rest_client.ex               # Checkpoint facade (uses Pristine.Core.Pipeline)
│       ├── types/                       # All ML types (sinter-validated)
│       │   ├── model_input.ex
│       │   ├── tensor_data.ex
│       │   └── ... (60+ files)
│       ├── regularizer.ex               # Behaviour
│       ├── regularizer/
│       │   ├── executor.ex
│       │   ├── pipeline.ex
│       │   ├── gradient_tracker.ex
│       │   └── telemetry.ex             # Emits to Pristine telemetry
│       ├── regularizers/
│       │   ├── l1.ex
│       │   ├── l2.ex
│       │   └── ... (8 files)
│       ├── recovery/
│       │   ├── policy.ex
│       │   ├── behaviours.ex
│       │   ├── executor.ex
│       │   └── monitor.ex
│       ├── streaming/
│       │   └── sample_stream.ex         # Uses Pristine.Streaming.SSEDecoder
│       ├── training/
│       │   └── custom_loss.ex
│       ├── metrics.ex                   # Emits to Pristine telemetry
│       ├── metrics_reduction.ex
│       ├── queue_state_observer.ex
│       ├── queue_state_logger.ex
│       ├── byte_estimator.ex
│       ├── tokenizer.ex
│       ├── tokenizer/
│       │   └── http_client.ex
│       ├── hugging_face.ex
│       ├── checkpoint_download.ex
│       ├── application.ex
│       └── cli/                         # OPTIONAL - CLI escript
│           ├── cli.ex
│           ├── parser.ex
│           ├── pagination.ex
│           ├── formatting.ex
│           └── commands/
│               ├── checkpoint.ex
│               ├── run.ex
│               ├── sample.ex
│               └── version.ex
├── priv/
│   └── manifest.exs                     # API definition + Sinter schemas
└── test/
    └── ...
```

**Estimated: ~60 files, ~4,000 LOC** (down from ~180 files, ~15,000 LOC)

---

## Dependency Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         examples/tinkex                           │
│    ┌───────────────────────────────────────────────────────┐     │
│    │              Domain Logic (~4,000 LOC)                 │     │
│    │  Clients | Types | Regularizers | Recovery | CLI(opt)  │     │
│    └───────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
                                │
                                │ uses
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│                         lib/pristine                              │
│    ┌────────────────────────────────────────────────────────┐    │
│    │                   Core Pipeline                         │    │
│    │   execute/5 | execute_stream/5 | execute_future/5       │    │
│    └────────────────────────────────────────────────────────┘    │
│    ┌──────────────────────┐  ┌────────────────────────────────┐  │
│    │        Ports         │  │           Adapters             │  │
│    │ Transport, Retry,    │  │ Finch, Foundation adapters,    │  │
│    │ CircuitBreaker,      │  │ Sinter JSON, MultipartEx,      │  │
│    │ RateLimit, Telemetry │  │ TelemetryReporter              │  │
│    └──────────────────────┘  └────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                                │
                                │ uses
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Local Dependencies                           │
│  ┌────────────┐ ┌────────┐ ┌─────────────┐ ┌──────────────────┐  │
│  │ foundation │ │ sinter │ │multipart_ex │ │telemetry_reporter│  │
│  │   retry    │ │ schema │ │  multipart  │ │   batch/send     │  │
│  │    cb      │ │ valid  │ │   encode    │ │                  │  │
│  │ rate limit │ │        │ │             │ │                  │  │
│  │  backoff   │ │        │ │             │ │                  │  │
│  └────────────┘ └────────┘ └─────────────┘ └──────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Validation Checklist

Before considering migration complete, verify:

- [ ] Zero infrastructure duplication in examples/tinkex
- [ ] All retry/circuit breaker/rate limit via foundation adapters
- [ ] All schema validation via sinter
- [ ] All multipart encoding via multipart_ex adapter
- [ ] All telemetry batching via telemetry_reporter adapter
- [ ] All HTTP via Pristine pipeline
- [ ] All streaming via Pristine SSEDecoder
- [ ] CLI (if included) only uses domain clients
- [ ] Types define structure, validation delegated to Sinter
- [ ] ~73% LOC reduction achieved (15k -> 4k)
