# Implementation Checklist - Tinkex Port

> Auto-maintained by iterative development agents
> Last updated: 2025-01-05

## Legend
- [ ] Not started
- [~] In progress
- [x] Complete
- [!] Blocked

---

## Phase 1: Project Foundation

### Infrastructure
- [ ] Create `examples/tinkex/` directory structure
- [ ] Create `examples/tinkex/mix.exs` with dependencies
- [ ] Create `examples/tinkex/lib/tinkex.ex` main module
- [ ] Create `examples/tinkex/lib/tinkex/application.ex`
- [ ] Configure local deps (foundation, sinter, multipart_ex, telemetry_reporter)
- [ ] Verify `mix compile` succeeds

### Configuration
- [ ] Tinkex.Config - configuration struct
- [ ] Tinkex.Env - environment variable parsing
- [ ] Config precedence: opts > app config > env > defaults

---

## Phase 2: Core Types (Sinter Schemas)

### Training Types
- [ ] Tinkex.Types.Datum
- [ ] Tinkex.Types.ModelInput
- [ ] Tinkex.Types.EncodedTextChunk
- [ ] Tinkex.Types.ImageChunk
- [ ] Tinkex.Types.ForwardBackwardInput
- [ ] Tinkex.Types.ForwardBackwardRequest
- [ ] Tinkex.Types.ForwardBackwardOutput
- [ ] Tinkex.Types.ForwardRequest
- [ ] Tinkex.Types.CustomLossOutput
- [ ] Tinkex.Types.TensorData
- [ ] Tinkex.Types.AdamParams
- [ ] Tinkex.Types.OptimStepRequest
- [ ] Tinkex.Types.OptimStepResponse

### Sampling Types
- [ ] Tinkex.Types.SampleRequest
- [ ] Tinkex.Types.SampleResponse
- [ ] Tinkex.Types.SampledSequence
- [ ] Tinkex.Types.SamplingParams
- [ ] Tinkex.Types.SampleStreamChunk
- [ ] Tinkex.Types.StopReason

### Session Types
- [ ] Tinkex.Types.CreateSessionRequest
- [ ] Tinkex.Types.CreateSessionResponse
- [ ] Tinkex.Types.GetSessionResponse
- [ ] Tinkex.Types.SessionHeartbeatRequest
- [ ] Tinkex.Types.SessionHeartbeatResponse
- [ ] Tinkex.Types.Checkpoint
- [ ] Tinkex.Types.CheckpointsListResponse
- [ ] Tinkex.Types.TrainingRun

### Model Types
- [ ] Tinkex.Types.CreateModelRequest
- [ ] Tinkex.Types.CreateModelResponse
- [ ] Tinkex.Types.LoraConfig
- [ ] Tinkex.Types.GetInfoRequest
- [ ] Tinkex.Types.GetInfoResponse
- [ ] Tinkex.Types.ModelData
- [ ] Tinkex.Types.LoadWeightsRequest
- [ ] Tinkex.Types.SaveWeightsRequest

### Async Types
- [ ] Tinkex.Types.FutureRetrieveRequest
- [ ] Tinkex.Types.FutureRetrieveResponse
- [ ] Tinkex.Types.FutureCompletedResponse
- [ ] Tinkex.Types.FuturePendingResponse
- [ ] Tinkex.Types.QueueState

### Error Types
- [ ] Tinkex.Types.RequestErrorCategory
- [ ] Tinkex.Types.RequestFailedResponse
- [ ] Tinkex.Error

---

## Phase 3: API Layer

### Core HTTP
- [ ] Tinkex.API - main HTTP client (uses pristine pipeline)
- [ ] Tinkex.API.Request - request preparation
- [ ] Tinkex.API.Response - response handling
- [ ] Tinkex.API.Headers - header construction
- [ ] Tinkex.API.URL - URL building

### Domain APIs
- [ ] Tinkex.API.Training - training endpoints
- [ ] Tinkex.API.Sampling - sampling endpoints
- [ ] Tinkex.API.Service - service/session endpoints
- [ ] Tinkex.API.Models - model endpoints
- [ ] Tinkex.API.Weights - weight endpoints
- [ ] Tinkex.API.Rest - REST endpoints
- [ ] Tinkex.API.Futures - future polling
- [ ] Tinkex.API.Telemetry - telemetry submission

### Streaming
- [ ] SSE decoder (or use Pristine.Streaming.SSEDecoder)
- [ ] Stream response handling

---

## Phase 4: Core Clients

### ServiceClient
- [ ] Tinkex.ServiceClient module
- [ ] start_link/1
- [ ] create_lora_training_client/3
- [ ] create_lora_training_client_async/3
- [ ] create_training_client_from_state/3
- [ ] create_sampling_client/2
- [ ] create_sampling_client_async/2
- [ ] create_rest_client/1
- [ ] telemetry_reporter/1

### TrainingClient
- [ ] Tinkex.TrainingClient module
- [ ] start_link/1
- [ ] get_info/1
- [ ] get_tokenizer/2
- [ ] encode/3
- [ ] decode/3
- [ ] forward_backward/4
- [ ] forward_backward_custom/4
- [ ] forward/4
- [ ] optim_step/2
- [ ] save_weights_and_get_sampling_client/2
- [ ] save_state/3
- [ ] load_state/3
- [ ] unload_model/1

### SamplingClient
- [ ] Tinkex.SamplingClient module
- [ ] start_link/1
- [ ] sample/4
- [ ] sample_stream/4
- [ ] sample_async/4

### RestClient
- [ ] Tinkex.RestClient module
- [ ] get_session/2
- [ ] list_sessions/2
- [ ] list_user_checkpoints/2
- [ ] get_checkpoint_archive_url/2
- [ ] delete_checkpoint/2
- [ ] get_weights_info/2
- [ ] get_sampler_info/2

---

## Phase 5: Resilience (via Foundation)

### Retry
- [ ] Map Tinkex.Retry to Foundation.Retry
- [ ] Map Tinkex.RetryHandler to Foundation.Retry.Handler
- [ ] Map Tinkex.RetryConfig to Foundation.Retry.Config

### Circuit Breaker
- [ ] Map Tinkex.CircuitBreaker to Foundation.CircuitBreaker
- [ ] Registry integration

### Rate Limiting
- [ ] Map Tinkex.RateLimiter to Foundation.RateLimit.BackoffWindow

### Future Polling
- [ ] Tinkex.Future using Foundation.Poller or pristine Future adapter

---

## Phase 6: Observability (via telemetry_reporter)

### Telemetry
- [ ] Tinkex.Telemetry module
- [ ] Tinkex.Telemetry.Reporter integration
- [ ] Event emission patterns

### Metrics
- [ ] Tinkex.Metrics module
- [ ] Counter/gauge/histogram support

---

## Phase 7: Tests

### Unit Tests
- [ ] Config tests
- [ ] Type validation tests
- [ ] API layer tests
- [ ] Client tests

### Integration Tests
- [ ] Training workflow test
- [ ] Sampling workflow test
- [ ] Session management test

### Quality Gates
- [ ] All tests passing
- [ ] Zero compile warnings
- [ ] Zero dialyzer errors
- [ ] Zero credo issues

---

## Phase 8: Examples Validation

### Port Source Examples
- [ ] training_loop.exs works
- [ ] sampling_basic.exs works
- [ ] checkpoint_management.exs works
- [ ] Custom loss examples work
- [ ] Streaming examples work

---

## Completion Criteria

- [ ] All 67+ types implemented
- [ ] All core client functions implemented
- [ ] API parity with source
- [ ] All tests passing
- [ ] mix dialyzer clean
- [ ] mix credo --strict clean
- [ ] Source examples run successfully
