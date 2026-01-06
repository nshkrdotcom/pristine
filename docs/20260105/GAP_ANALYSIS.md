# Gap Analysis - Tinkex Port (Examples-Driven)

> Auto-maintained by iterative development agents
> Last updated: 2026-01-05 (Iteration 1 - State Assessment Complete)
> **Focus**: Full surface area from ALL source examples

## Executive Summary

| Metric | Value |
|--------|-------|
| Source modules | **185** |
| Source types | **76** (67 main + 9 telemetry) |
| Source examples | **33** |
| Source tests | **999** across 125 files |
| Port modules | **22** (Config + 18 types + 2 resources + 1 client) |
| Port endpoints | 6 |
| **Gap: Missing types** | **58** (76 - 18 ported) |
| **Gap: Missing client functions** | **84** |
| **Gap: Missing API endpoints** | **35** |
| **Gap: Missing test files** | **121** |
| Completion % | **~12%** |
| Port tests | **126** passing |
| Blocking issues | None |

### Agent Analysis Summary (2026-01-05)
- **Core Clients Gap**: 84 public functions across 4 clients (0 ported)
- **API Layer Gap**: 35 endpoints missing (7 API modules)
- **Types Gap**: 62 types missing from 76 total (14 ported including all training types)
  - Ported: ModelInput, EncodedTextChunk, ImageChunk, ImageAssetPointerChunk, LoraConfig, AdamParams, TensorDtype, TensorData, Datum + 5 generated
- **Test Coverage Gap**: 121 test files missing (98%)
- **Telemetry Coverage**: ~60% via Pristine adapters
- **Resilience Coverage**: ~95% via Foundation adapters (Recovery system needs custom)

### Critical Finding

The current port (`./examples/tinkex/generated/`) is a **manifest-generated simple client** suitable for basic sampling and model listing. However, the source examples demonstrate a **full-featured ML training SDK** requiring:

1. **GenServer-based clients** with stateful session management
2. **Training workflows** with forward/backward passes, optimizer steps
3. **Checkpoint management** with save/load/download capabilities
4. **Telemetry & recovery** infrastructure
5. **Custom loss functions** and regularizers
6. **Queue state management** for throttling

---

## Source Examples Inventory (33 files)

### Example Categories by API Surface Required

#### Category 1: Basic Sampling (Port Covers ~60%)
| Example | Status | Missing |
|---------|--------|---------|
| sampling_basic.exs | Partial | ServiceClient, ModelInput, Tokenizer |
| kimi_k2_sampling_live.exs | Partial | Server capabilities, Tokenizer |

#### Category 2: Training Workflows (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| training_loop.exs | Not covered | TrainingClient, forward_backward, optim_step |
| adam_and_chunking_live.exs | Not covered | AdamParams, DataProcessor.chunk_data |
| forward_inference.exs | Not covered | TrainingClient.forward, TensorData, Nx integration |
| custom_loss_training.exs | Not covered | forward_backward_custom, CustomLossOutput |
| structured_regularizers.exs | Not covered | Regularizer.Pipeline, all regularizers |
| structured_regularizers_live.exs | Not covered | NxPenalties integration |
| save_weights_and_sample.exs | Not covered | save_weights_and_get_sampling_client_sync |

#### Category 3: Checkpoint Management (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| checkpoints_management.exs | Not covered | RestClient, list_user_checkpoints |
| checkpoint_download.exs | Not covered | CheckpointDownload module |
| checkpoint_multi_delete_live.exs | Not covered | CLI, batch operations |
| training_persistence_live.exs | Not covered | save_state, load_state_with_optimizer |
| weights_inspection.exs | Not covered | Rest.list_training_runs, get_training_run |

#### Category 4: Async & Futures (Port Covers ~20%)
| Example | Status | Missing |
|---------|--------|---------|
| async_client_creation.exs | Partial | Async client creation variants |
| model_info_and_unload.exs | Not covered | Futures.retrieve, Models.get_info/unload_model |

#### Category 5: Session Management (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| sessions_management.exs | Not covered | RestClient session operations |
| heartbeat_probe.exs | Not covered | Session.create, heartbeat API |

#### Category 6: Telemetry & Observability (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| telemetry_reporter_demo.exs | Not covered | Reporter module, exception handling |
| telemetry_live.exs | Not covered | Telemetry.attach_logger/detach |
| metrics_live.exs | Not covered | Metrics.reset/flush/snapshot |
| retry_and_capture.exs | Not covered | Retry.with_retry, Capture.capture_exceptions |

#### Category 7: Recovery (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| recovery_simulated.exs | Not covered | Recovery.{Executor, Monitor, Policy} |
| recovery_live_injected.exs | Not covered | Full recovery infrastructure |

#### Category 8: Queue & Throttling (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| queue_reasons_and_sampling_throttling.exs | Not covered | QueueStateLogger, SamplingDispatch |
| queue_state_observer_demo.exs | Not covered | QueueStateObserver behaviour |

#### Category 9: CLI (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| cli_run_text.exs | Not covered | CLI.run |
| cli_run_prompt_file.exs | Not covered | CLI with file I/O |

#### Category 10: Advanced Features (Port Covers 0%)
| Example | Status | Missing |
|---------|--------|---------|
| multimodal_resume_and_cleanup.exs | Not covered | ImageChunk, vision models |
| file_upload_multipart.exs | Not covered | Multipart encoding |
| llama3_tokenizer_override_live.exs | Not covered | Tokenizer override |
| live_capabilities_and_logprobs.exs | Not covered | compute_logprobs |

---

## Missing API Surface by Module

### Core Clients (GenServer-based) - Detailed Function Gap

**Total Missing Functions: 84** (0 ported)

#### Tinkex.ServiceClient (15 functions MISSING)
Required by: 28 examples

| Function | Arity | Notes |
|----------|-------|-------|
| start_link | 1 | GenServer entry point, accepts `:config` opts |
| create_lora_training_client | 3 | Creates TrainingClient with base_model |
| create_lora_training_client_async | 3 | Async variant returning Task.t() |
| create_training_client_from_state | 3 | Load from checkpoint path |
| create_training_client_from_state_with_optimizer | 3 | Checkpoint + optimizer state |
| create_training_client_from_state_async | 3 | Async variant |
| create_training_client_from_state_with_optimizer_async | 3 | Async variant with optimizer |
| create_sampling_client | 2 | Creates SamplingClient |
| create_sampling_client_async | 2 | Async variant |
| get_server_capabilities | 1 | Fetch server capabilities |
| get_server_capabilities_async | 1 | Async variant |
| create_rest_client | 1 | Returns RestClient struct |
| telemetry_reporter | 1 | Get telemetry reporter pid |
| get_telemetry | 0 | Process dictionary telemetry |
| get_telemetry | 1 | GenServer call for telemetry |

**GenServer Callbacks Needed:** `init/1`, `handle_call/3` (12 clauses), `terminate/2`

#### Tinkex.TrainingClient (MISSING)
Required by: 12 examples
```elixir
# Functions needed:
forward/4
forward_backward/4
forward_backward_custom/4
optim_step/2
save_state/2
load_state/2
load_state_with_optimizer/2
save_weights_for_sampler/2
save_weights_and_get_sampling_client_sync/1
unload_model/1
# Nested: DataProcessor.chunk_data/1
```

#### Tinkex.SamplingClient (PARTIAL - needs extension)
Required by: 15 examples
```elixir
# Additional functions needed:
sample/4 with queue_state_observer option
compute_logprobs/2
# Current port has basic sample via generated client
```

#### Tinkex.RestClient (MISSING)
Required by: 8 examples
```elixir
# Functions needed:
list_sessions/2
get_session/2
list_user_checkpoints/2
list_checkpoints/2
get_checkpoint_archive_url/2
delete_checkpoint/2
```

### API Layer Modules (MISSING)

| Module | Required Functions | Examples Using |
|--------|-------------------|----------------|
| Tinkex.API.Session | create/2, create_typed/2 | heartbeat_probe, model_info_and_unload |
| Tinkex.API.Service | create_model/2, get_server_capabilities/2, health_check/2 | model_info_and_unload, live_capabilities |
| Tinkex.API.Models | get_info/2, unload_model/2 | model_info_and_unload |
| Tinkex.API.Futures | retrieve/2 | model_info_and_unload, async patterns |
| Tinkex.API.Rest | list_training_runs/3, get_training_run/2 | weights_inspection |

### Missing Types (55+)

#### Training Types (15)
| Type | Fields | Examples Using |
|------|--------|----------------|
| LoraConfig | rank, seed, train_mlp, train_attn, train_unembed | 12 examples |
| AdamParams | learning_rate, beta1, beta2, eps, weight_decay, grad_clip_norm | 8 examples |
| Datum | model_input, loss_fn_inputs | 10 examples |
| TensorData | data, dtype, shape | 8 examples |
| TensorDtype | :int64, :float32 | 8 examples |
| ModelInput | chunks (array of chunk types) | 20 examples |
| EncodedTextChunk | tokens, type | 15 examples |
| ImageChunk | data, format, expected_tokens | 2 examples |
| ImageAssetPointerChunk | location, format, expected_tokens | 1 example |
| ForwardBackwardInput | data, loss_fn, loss_fn_config | 10 examples |
| ForwardBackwardRequest | forward_backward_input, model_id, seq_id | 10 examples |
| ForwardBackwardOutput | loss_fn_output_type, loss_fn_outputs, metrics | 10 examples |
| ForwardRequest | forward_input, model_id, seq_id | 2 examples |
| OptimStepRequest | adam_params, model_id, seq_id | 8 examples |
| OptimStepResponse | metrics | 8 examples |

#### Loss & Regularizer Types (5)
| Type | Fields | Examples Using |
|------|--------|----------------|
| LossFnType | :cross_entropy, :importance_sampling, :ppo, :cispo, :dro | 10 examples |
| RegularizerSpec | fn, weight, name, async | 2 examples |
| RegularizerOutput | name, value, weight, contribution, grad_norm, custom | 2 examples |
| CustomLossOutput | loss_total, base_loss, regularizers, regularizer_total, total_grad_norm | 3 examples |

#### Session & Model Types (12)
| Type | Examples Using |
|------|----------------|
| CreateSessionRequest | 2 examples |
| CreateSessionResponse | 2 examples |
| CreateModelRequest | 2 examples |
| CreateModelResponse | 2 examples |
| CreateSamplingSessionRequest | 5 examples |
| CreateSamplingSessionResponse | 5 examples |
| GetInfoRequest | 1 example |
| GetInfoResponse | 1 example |
| UnloadModelRequest | 1 example |
| UnloadModelResponse | 1 example |
| ModelData | 1 example |
| SessionHeartbeatRequest/Response | 1 example |

#### Checkpoint & Weight Types (12)
| Type | Examples Using |
|------|----------------|
| Checkpoint | 5 examples |
| CheckpointsListResponse | 3 examples |
| CheckpointArchiveUrlResponse | 1 example |
| ParsedCheckpointTinkerPath | 2 examples |
| TrainingRun | 3 examples |
| TrainingRunsResponse | 1 example |
| LoadWeightsRequest | 3 examples |
| LoadWeightsResponse | 3 examples |
| SaveWeightsRequest | 5 examples |
| SaveWeightsResponse | 5 examples |
| SaveWeightsForSamplerRequest | 4 examples |
| SaveWeightsForSamplerResponse | 4 examples |
| WeightsInfoResponse | 1 example |
| Cursor | 3 examples |

#### Future & Async Types (6)
| Type | Examples Using |
|------|----------------|
| FutureRetrieveRequest | 2 examples |
| FuturePendingResponse | 2 examples |
| FutureCompletedResponse | 2 examples |
| FutureFailedResponse | 1 example |
| TryAgainResponse | 3 examples |
| QueueState | 3 examples |

#### Sampling Types (Port has partial)
| Type | Status | Missing Fields |
|------|--------|----------------|
| SamplingParams | Need full | top_k, seed, stop variants |
| SampledSequence | MISSING | tokens, logprobs, stop_reason |
| StopReason | MISSING | :length, :stop enum |
| SampleStreamChunk | Partial | event_type, finish_reason |

#### Error & Misc Types (5)
| Type | Examples Using |
|------|----------------|
| RequestErrorCategory | 2 examples |
| RequestFailedResponse | 1 example |
| HealthResponse | 1 example |
| GetServerCapabilitiesResponse | 3 examples |
| SupportedModel | 3 examples |
| GetSessionResponse | 1 example |
| ListSessionsResponse | 1 example |
| GetSamplerResponse | 1 example |

### Missing Feature Modules

#### Tinkex.Tokenizer (MISSING)
Required by: 10 examples
```elixir
encode/2  # text -> token_ids
decode/2  # token_ids -> text
```

#### Tinkex.Recovery (MISSING)
Required by: 2 examples
```elixir
Tinkex.Recovery.Policy.new/1
Tinkex.Recovery.Executor.start_link/1
Tinkex.Recovery.Monitor.start_link/1
Tinkex.Recovery.Monitor.monitor_run/4
```

#### Tinkex.Regularizer (MISSING)
Required by: 2 examples
```elixir
Tinkex.Regularizer.Pipeline.compute/4
Tinkex.Regularizer.Executor.execute_one/4
Tinkex.Regularizer.Executor.execute_all/4
Tinkex.Regularizer.GradientTracker.compute_grad_norm/2
Tinkex.Regularizer.Telemetry.attach_logger/1
```

#### Tinkex.Regularizers.* (MISSING)
Required by: 2 examples
```elixir
L1.compute/3, L2.compute/3, ElasticNet.compute/3
Entropy.compute/3, KLDivergence.compute/3
Consistency.compute/3, Orthogonality.compute/3
GradientPenalty.compute/3
```

#### Tinkex.Telemetry.Reporter (MISSING)
Required by: 4 examples
```elixir
start_link/1
log/3, log/4
log_exception/3
flush/2
wait_until_drained/2
stop/2
```

#### Tinkex.Metrics (MISSING)
Required by: 1 example
```elixir
reset/0
flush/0
snapshot/0
```

#### Tinkex.CLI (MISSING)
Required by: 3 examples
```elixir
run/1  # Execute CLI commands
```

#### Tinkex.CheckpointDownload (MISSING)
Required by: 1 example
```elixir
download/3  # Download and extract checkpoint archives
```

#### Queue & Dispatch (MISSING)
Required by: 2 examples
```elixir
Tinkex.QueueStateLogger.log_state_change/4
Tinkex.SamplingDispatch.set_backoff/2
Tinkex.SamplingDispatch.with_rate_limit/3
Tinkex.ByteEstimator.estimate_model_input_bytes/1
```

#### Tinkex.Config (MISSING)
Required by: ALL examples
```elixir
new/0, new/1
# Fields: api_key, base_url, recovery, user_metadata, etc.
```

---

## Pristine Integration Points

### Available (Can Reuse)

| Pristine Component | Tinkex Equivalent | Status |
|-------------------|-------------------|--------|
| Pristine.Ports.Transport | HTTP client | Available |
| Pristine.Ports.Retry | Retry logic | Available |
| Pristine.Ports.CircuitBreaker | Circuit breaker | Available |
| Pristine.Ports.RateLimit | Rate limiting | Available |
| Pristine.Ports.Telemetry | Telemetry emission | Available |
| Pristine.Ports.Serializer | JSON encoding | Available |
| Pristine.Ports.Future | Polling futures | Available |
| Pristine.Streaming.SSEDecoder | SSE parsing | Available |
| Foundation.Retry | Retry policies | Available |
| Foundation.CircuitBreaker | Circuit breaker | Available |
| Foundation.RateLimit.BackoffWindow | Rate limiting | Available |
| Sinter.Schema | Type validation | Available |

### Gaps (Need New Adapters or Modules)

| Feature | Port Needed | Notes |
|---------|------------|-------|
| Nx Tensor Integration | Custom | For TensorData <-> Nx.Tensor |
| Tokenizer | Custom | TiktokenEx + model-specific |
| Recovery System | New module | Not in pristine |
| Regularizers | New module | Nx-based computations |
| Metrics Collection | New module | Custom histogram/counter |
| CLI Framework | New module | Command parsing |

---

## Implementation Priority Queue

### Phase 1: Foundation (Enables 60% of examples)
1. Tinkex.Config - Required by all examples
2. Core types: LoraConfig, AdamParams, ModelInput, Datum, TensorData
3. Tinkex.ServiceClient - Main entry point
4. Tinkex.Tokenizer - encode/decode

### Phase 2: Training (Enables 80% of examples)
5. Tinkex.TrainingClient - Training operations
6. Training types: ForwardBackwardInput/Output, OptimStepRequest/Response
7. Checkpoint types: Checkpoint, SaveWeightsResponse, LoadWeightsResponse

### Phase 3: REST & Sessions (Enables 90% of examples)
8. Tinkex.RestClient - REST operations
9. Session types: CreateSessionRequest/Response
10. API modules: Session, Service, Models, Futures

### Phase 4: Telemetry & Resilience (Enables 95% of examples)
11. Tinkex.Telemetry.Reporter
12. Tinkex.Metrics
13. Tinkex.Recovery (Executor, Monitor, Policy)

### Phase 5: Advanced Features (Enables 100%)
14. Regularizer system
15. CLI
16. QueueState/Dispatch
17. CheckpointDownload

---

## Decisions Required

1. **Type implementation**: Port source types directly OR regenerate via Sinter schemas?
   - Recommendation: Sinter schemas for validation, matching source API

2. **GenServer vs Pipeline**: Port GenServer clients OR use pristine pipeline?
   - Recommendation: Keep GenServer pattern for session state, use pristine for HTTP

3. **Nx integration**: Bundle Nx dependency OR make optional?
   - Recommendation: Optional dependency, TensorData provides Nx conversion when available

4. **Test strategy**: Port 999 source tests OR write new tests?
   - Recommendation: Write new tests against port, use source tests as reference

---

## Notes

- Source uses GenServer extensively for client state management
- Source has Python SDK parity requirement - maintained in port
- Many examples require `:telemetry.attach/attach_many` integration
- NxPenalties is external dep for regularizers - need to verify availability

---

## Complete Source Type Catalog (75 Types)

### Main Types (66)

| Module | Struct Fields | Purpose |
|--------|---------------|---------|
| AdamParams | learning_rate, beta1, beta2, eps, weight_decay, grad_clip_norm | Adam optimizer parameters |
| Checkpoint | checkpoint_id, checkpoint_type, tinker_path, training_run_id, size_bytes, public, time | Checkpoint metadata |
| CheckpointArchiveUrlResponse | url, expires | Download URL for checkpoint archives |
| CheckpointsListResponse | checkpoints, cursor | Paginated checkpoint list |
| CreateModelRequest | session_id, model_seq_id, base_model, user_metadata, lora_config, type | Model creation request |
| CreateModelResponse | model_id | Model creation response |
| CreateSamplingSessionRequest | session_id, sampling_session_seq_id, base_model, model_path, type | Sampling session creation |
| CreateSamplingSessionResponse | sampling_session_id | Sampling session response |
| CreateSessionRequest | tags, user_metadata, sdk_version, type | Session creation request |
| CreateSessionResponse | session_id, info_message, warning_message, error_message | Session creation response |
| Cursor | offset, limit, total_count | Pagination cursor |
| CustomLossOutput | loss_total, base_loss, regularizer_total, total_grad_norm, regularizers | Custom loss output |
| Datum | model_input, loss_fn_inputs | Training example |
| EncodedTextChunk | tokens, type | Encoded text chunk |
| ForwardBackwardInput | data, loss_fn, loss_fn_config | Forward-backward input |
| ForwardBackwardOutput | loss_fn_output_type, loss_fn_outputs, metrics | Forward-backward output |
| ForwardBackwardRequest | forward_backward_input, model_id, seq_id | Forward-backward request |
| ForwardRequest | forward_input, model_id, seq_id | Forward-only request |
| FuturePendingResponse | status | Future pending status |
| FutureCompletedResponse | status, result | Future completed status |
| FutureFailedResponse | status, error | Future failed status |
| FutureRetrieveRequest | request_id | Future retrieval request |
| GetInfoRequest | model_id, type | Model info request |
| GetInfoResponse | model_id, model_data, is_lora, lora_rank, model_name, type | Model info response |
| GetSamplerResponse | sampler_id, base_model, model_path | Sampler info response |
| GetServerCapabilitiesResponse | supported_models | Server capabilities |
| GetSessionResponse | training_run_ids, sampler_ids | Session info response |
| HealthResponse | status | Health check response |
| ImageAssetPointerChunk | location, format, expected_tokens, type | Image asset reference |
| ImageChunk | data, format, expected_tokens, type | Image chunk with base64 |
| ListSessionsResponse | sessions | Session list response |
| LoadWeightsRequest | model_id, path, seq_id, optimizer, type | Weight loading request |
| LoadWeightsResponse | path, type | Weight loading response |
| LoraConfig | rank, seed, train_mlp, train_attn, train_unembed | LoRA configuration |
| LossFnType | (enum) | Loss function type enumeration |
| ModelData | arch, model_name, tokenizer_id | Model metadata |
| ModelInput | chunks | Model input with chunks |
| OptimStepRequest | adam_params, model_id, seq_id | Optimizer step request |
| OptimStepResponse | metrics | Optimizer step response |
| ParsedCheckpointTinkerPath | tinker_path, training_run_id, checkpoint_type, checkpoint_id | Parsed tinker path |
| QueueState | (enum) | Queue state enumeration |
| RegularizerOutput | name, value, weight, contribution, grad_norm, grad_norm_weighted, custom | Regularizer output |
| RegularizerSpec | fn, weight, name, async | Regularizer specification |
| RequestErrorCategory | (enum) | Error category enumeration |
| RequestFailedResponse | error, category | Request failure response |
| SampleRequest | sampling_session_id, seq_id, base_model, model_path, prompt, sampling_params, num_samples, prompt_logprobs, topk_prompt_logprobs, type | Sample request |
| SampleResponse | sequences, prompt_logprobs, topk_prompt_logprobs, type | Sample response |
| SampleStreamChunk | token, token_id, index, finish_reason, total_tokens, logprob, event_type | Stream chunk |
| SampledSequence | tokens, logprobs, stop_reason | Sampled sequence |
| SamplingParams | max_tokens, seed, stop, temperature, top_k, top_p | Sampling parameters |
| SaveWeightsForSamplerRequest | model_id, path, sampling_session_seq_id, seq_id, type | Save weights for sampler |
| SaveWeightsForSamplerResponse | path, sampling_session_id, type | Save weights response |
| SaveWeightsRequest | model_id, path, seq_id, type | Save weights request |
| SaveWeightsResponse | path, type | Save weights response |
| SessionHeartbeatRequest | session_id, type | Heartbeat request |
| SessionHeartbeatResponse | type | Heartbeat response |
| StopReason | (enum) | Stop reason enumeration |
| SupportedModel | model_id, model_name, arch | Supported model info |
| TensorData | data, dtype, shape | Tensor data container |
| TensorDtype | (enum) | Tensor data type |
| TrainingRun | training_run_id, base_model, model_owner, is_lora, lora_rank, corrupted, last_request_time, last_checkpoint, last_sampler_checkpoint, user_metadata | Training run metadata |
| TrainingRunsResponse | training_runs, cursor | Training runs list |
| TryAgainResponse | type, request_id, queue_state, retry_after_ms, queue_state_reason | Retry response |
| TypeAliases | (type definitions) | Type aliases |
| UnloadModelRequest | model_id, type | Model unload request |
| UnloadModelResponse | model_id, type | Model unload response |
| WeightsInfoResponse | base_model, is_lora, lora_rank | Weights info response |

### Telemetry Types (9)

| Module | Struct Fields | Purpose |
|--------|---------------|---------|
| Telemetry.EventType | (enum) | Event type enumeration |
| Telemetry.GenericEvent | event, event_id, event_session_index, severity, timestamp, event_name, event_data | Generic event |
| Telemetry.SessionEndEvent | event, event_id, event_session_index, severity, timestamp, duration | Session end event |
| Telemetry.SessionStartEvent | event, event_id, event_session_index, severity, timestamp | Session start event |
| Telemetry.Severity | (enum) | Severity enumeration |
| Telemetry.TelemetryBatch | events, metadata | Event batch |
| Telemetry.TelemetryEvent | (union type) | Union telemetry event |
| Telemetry.TelemetrySendRequest | session_id, platform, sdk_version, events | Telemetry send request |
| Telemetry.UnhandledExceptionEvent | event, event_id, event_session_index, severity, timestamp, error_type, error_message, traceback | Exception event |
| TelemetryResponse | status | Telemetry send response |

---

## Pristine Infrastructure Mapping

### Available Ports & Adapters

| Pristine Port | Primary Adapter | Tinkex Use Case |
|--------------|----------------|-----------------|
| Transport | Finch | HTTP requests |
| StreamTransport | FinchStream | SSE streaming |
| Serializer | JSON | JSON encoding with Sinter validation |
| Auth | Bearer, ApiKey | API authentication |
| Retry | Foundation | Exponential backoff, Retry-After |
| RateLimit | BackoffWindow | Request throttling |
| CircuitBreaker | Foundation | Fault tolerance |
| Semaphore | Counting | Connection limiting |
| Multipart | Ex | File uploads |
| Tokenizer | Tiktoken | Token counting |
| Telemetry | Foundation, Reporter | Observability |
| Future | Polling | Async operation polling |

### Port Configuration for Tinkex

```elixir
# Minimal viable context
Context.new(
  base_url: System.get_env("TINKER_BASE_URL"),
  auth: [{Pristine.Adapters.Auth.Bearer, [token: api_key]}],
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: Tinkex.Finch],
  stream_transport: Pristine.Adapters.Transport.FinchStream,
  serializer: Pristine.Adapters.Serializer.JSON,
  retry: Pristine.Adapters.Retry.Foundation,
  retry_opts: [max_attempts: 3, backoff: :exponential],
  rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow,
  circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
  telemetry: Pristine.Adapters.Telemetry.Foundation
)
```

### Infrastructure Gaps (Need New Implementation)

| Feature | Notes |
|---------|-------|
| GenServer Clients | ServiceClient, TrainingClient, SamplingClient, RestClient |
| Nx Tensor Integration | TensorData <-> Nx.Tensor conversion |
| Model-specific Tokenizer | HuggingFace tokenizer selection |
| Recovery System | Monitor, Executor, Policy modules |
| Regularizers | 8 regularizer implementations with Nx |
| Metrics Collection | Custom histogram/counter ETS |
| CLI Framework | Command parsing and execution |
| Queue State Observer | Behaviour for state change callbacks |
