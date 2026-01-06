# Implementation Checklist - 2025-01-06

## Legend

- [ ] Not started
- [~] In progress
- [x] Complete
- [!] Blocked

---

## Core Infrastructure

- [x] Project structure (examples/tinkex/)
- [x] mix.exs with dependencies (via parent project)
- [x] Config module
- [x] Error handling
- [x] HTTPClient behaviour

---

## Core Clients

### Tinkex (Main Entry)

- [x] `new/1` - Create service client
- [x] `new!/1` - Create service client (raising)
- [x] `create_training_client/3`
- [x] `create_sampling_client/2`
- [x] `create_rest_client/1`
- [x] `get_server_capabilities/1`
- [x] `version/0`

### Tinkex.ServiceClient

- [x] `new/2`
- [x] `create_lora_training_client/4`
- [x] `create_training_client_from_state/4`
- [x] `create_sampling_client/2`
- [x] `create_rest_client/1`
- [x] `get_server_capabilities/1`
- [x] `session_id/1`
- [x] `config/1`
- [x] `next_training_seq_id/1`
- [x] `next_sampling_seq_id/1`
- [x] `create_lora_training_client_async/3` **DONE 2025-01-06**
- [x] `create_training_client_from_state_async/3` **DONE 2025-01-06**
- [x] `create_sampling_client_async/2` **DONE 2025-01-06**
- [x] `get_server_capabilities_async/1` **DONE 2025-01-06**
- [x] `telemetry_reporter/1` **DONE 2025-01-06**
- [x] `get_telemetry/0` **DONE 2025-01-06**
- [x] `get_telemetry/1` **DONE 2025-01-06**

### Tinkex.TrainingClient

- [x] `new/4`
- [x] `forward_backward/4`
- [x] `forward/3`
- [x] `optim_step/3`
- [x] `save_state/3`
- [x] `load_state/3`
- [x] `save_weights_for_sampler/3`
- [x] `next_seq_id/1`
- [x] `parse_forward_backward_response/1`
- [x] `get_info/1` **DONE**
- [x] `get_tokenizer/2` **DONE**
- [x] `encode/3` **DONE**
- [x] `decode/3` **DONE**
- [x] `unload_model/1` **DONE**
- [x] `forward_backward_custom/4` **DONE 2025-01-06**
- [x] `save_weights_and_get_sampling_client/2` **DONE 2025-01-06**
- [x] `load_state_with_optimizer/3` **DONE 2025-01-06**
- [x] `on_queue_state_change/2` **DONE 2025-01-06**

### Tinkex.TrainingClient Submodules (NEW 2025-01-06)

- [x] `Tinkex.TrainingClient.DataProcessor` - Data chunking, ID allocation, tensor ops
- [x] `Tinkex.TrainingClient.Observer` - Queue state observation with debouncing
- [x] `Tinkex.TrainingClient.Operations` - Request building and execution
- [x] `Tinkex.TrainingClient.Polling` - Future polling and result awaiting
- [x] `Tinkex.TrainingClient.Tokenizer` - Tokenizer integration

### Tinkex.SamplingClient

- [x] `new/3`
- [x] `sample/4`
- [x] `sample_stream/4`
- [x] `compute_logprobs/3`
- [x] `next_seq_id/1`
- [x] `parse_sample_response/1`
- [x] `on_queue_state_change/2` **DONE 2025-01-06**
- [x] `on_queue_state_change/3` **DONE 2025-01-06**
- [x] `clear_queue_state_debounce/1` **DONE 2025-01-06**
- [x] `create_async/2` **DONE 2025-01-06**

### Tinkex.RestClient

- [x] `new/3`
- [x] `get_session/2`
- [x] `list_sessions/2`
- [x] `get_sampler/2`
- [x] `get_weights_info_by_tinker_path/2`
- [x] `list_checkpoints/2`
- [x] `list_user_checkpoints/2`
- [x] `get_checkpoint_archive_url/2`
- [x] `get_checkpoint_archive_url/3`
- [x] `delete_checkpoint/2`
- [x] `delete_checkpoint/3`
- [x] `publish_checkpoint/2`
- [x] `unpublish_checkpoint/2`
- [x] `get_training_run/2`
- [x] `get_training_run_by_tinker_path/2`
- [x] `list_training_runs/2`
- [x] All `*_async` variants
- [x] `delete_checkpoint_by_tinker_path/2` (alias) **DONE 2025-01-06**
- [x] `publish_checkpoint_from_tinker_path/2` (alias) **DONE 2025-01-06**
- [x] `unpublish_checkpoint_from_tinker_path/2` (alias) **DONE 2025-01-06**
- [x] `get_checkpoint_archive_url_by_tinker_path/2` (alias) **DONE 2025-01-06**
- [x] All `*_by_tinker_path_async` variants **DONE 2025-01-06**

---

## API Layer

- [x] Tinkex.API
- [x] Tinkex.API.Session
- [x] Tinkex.API.Service
- [x] Tinkex.API.Training
- [x] Tinkex.API.Sampling
- [x] Tinkex.API.Weights
- [x] Tinkex.API.Rest
- [x] Tinkex.API.Futures
- [x] Tinkex.API.Telemetry **DONE 2025-01-06**
- [x] Tinkex.API.Retry **DONE 2025-01-06**
- [x] Tinkex.API.RetryConfig **DONE 2025-01-06**
- [x] Tinkex.API.URL **DONE 2025-01-06**
- [x] Tinkex.API.Headers **DONE 2025-01-06**
- [x] Tinkex.API.Compression **DONE 2025-01-06**
- [x] Tinkex.API.Helpers **DONE 2025-01-06**
- [x] Tinkex.API.Response **DONE 2025-01-06**
- [x] Tinkex.API.Request **DONE 2025-01-06**
- [x] Tinkex.API.ResponseHandler **DONE 2025-01-06**
- [x] Tinkex.API.StreamResponse **DONE 2025-01-06**

---

## Types (75/75 Complete)

### Core Types (Complete)

- [x] Datum
- [x] ModelInput
- [x] TensorData
- [x] TensorDtype
- [x] SamplingParams
- [x] SampledSequence
- [x] SampleStreamChunk
- [x] Checkpoint
- [x] LoraConfig
- [x] AdamParams
- [x] LossFnType
- [x] StopReason
- [x] QueueState
- [x] Cursor
- [x] CustomLossOutput
- [x] RegularizerOutput
- [x] RegularizerSpec
- [x] RequestErrorCategory
- [x] ParsedCheckpointTinkerPath
- [x] ... (47 more complete)

### Telemetry Types (Complete) **DONE 2025-01-06**

- [x] Tinkex.Types.Telemetry.EventType
- [x] Tinkex.Types.Telemetry.Severity
- [x] Tinkex.Types.Telemetry.GenericEvent
- [x] Tinkex.Types.Telemetry.SessionStartEvent
- [x] Tinkex.Types.Telemetry.SessionEndEvent
- [x] Tinkex.Types.Telemetry.UnhandledExceptionEvent
- [x] Tinkex.Types.Telemetry.TelemetryEvent
- [x] Tinkex.Types.Telemetry.TelemetryBatch
- [x] Tinkex.Types.Telemetry.TelemetrySendRequest

---

## Telemetry Infrastructure

- [x] Tinkex.Telemetry
- [x] Tinkex.Telemetry.Capture
- [x] Tinkex.Telemetry.Reporter
- [x] Tinkex.Telemetry.Provider **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Otel **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Reporter.Queue **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Reporter.Events **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Reporter.Backoff **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Reporter.Serializer **DONE 2025-01-06**
- [x] Tinkex.Telemetry.Reporter.ExceptionHandler **DONE 2025-01-06**

---

## Resilience

- [x] Tinkex.Retry
- [x] Tinkex.RetryHandler
- [x] Tinkex.RateLimiter
- [x] Tinkex.BytesSemaphore
- [x] Tinkex.Semaphore (NEW - unstaged)
- [x] Tinkex.SamplingDispatch (NEW - unstaged)
- [x] Tinkex.PoolKey
- [x] Tinkex.CircuitBreaker **DONE 2025-01-06**
- [x] Tinkex.CircuitBreaker.Registry **DONE 2025-01-06**
- [x] Tinkex.RetryConfig **DONE 2025-01-06**

---

## Recovery

- [x] Tinkex.Recovery.Policy
- [x] Tinkex.Recovery.Behaviours
- [x] Tinkex.Recovery.Executor
- [x] Tinkex.Recovery.Monitor

---

## Regularizer

- [x] Tinkex.Regularizer
- [x] Tinkex.Regularizer.Telemetry
- [x] Tinkex.Regularizer.Executor **DONE 2025-01-06**
- [x] Tinkex.Regularizer.Pipeline **DONE 2025-01-06**
- [x] Tinkex.Regularizer.GradientTracker **DONE 2025-01-06**

## Regularizer Implementations

- [x] Tinkex.Regularizers.L1 **DONE 2025-01-06**
- [x] Tinkex.Regularizers.L2 **DONE 2025-01-06**
- [x] Tinkex.Regularizers.ElasticNet **DONE 2025-01-06**
- [x] Tinkex.Regularizers.Entropy **DONE 2025-01-06**
- [x] Tinkex.Regularizers.KLDivergence **DONE 2025-01-06**
- [x] Tinkex.Regularizers.Consistency **DONE 2025-01-06**
- [x] Tinkex.Regularizers.GradientPenalty **DONE 2025-01-06**
- [x] Tinkex.Regularizers.Orthogonality **DONE 2025-01-06**

---

## Observability

- [x] Tinkex.QueueStateObserver
- [x] Tinkex.QueueStateLogger
- [x] Tinkex.Metrics
- [x] Tinkex.ByteEstimator

---

## Streaming

- [x] Tinkex.Streaming.SampleStream
- [x] Tinkex.Streaming.SSEDecoder **DONE 2025-01-06**
- [x] Tinkex.Streaming.ServerSentEvent **DONE 2025-01-06**

---

## Supporting Modules

- [x] Tinkex.Future
- [x] Tinkex.Tokenizer
- [x] Tinkex.HuggingFace

---

## Utility Modules

- [x] Tinkex.NotGiven **DONE 2025-01-06**
- [x] Tinkex.Transform **DONE 2025-01-06**
- [x] Tinkex.Logging **DONE 2025-01-06**
- [x] Tinkex.SamplingRegistry **DONE 2025-01-06**
- [x] Tinkex.Env **DONE 2025-01-06**
- [x] Tinkex.SessionManager **DONE 2025-01-06**
- [x] Tinkex.Application **DONE 2025-01-06**
- [x] Tinkex.MetricsReduction **DONE 2025-01-06**
- [x] Tinkex.RetrySemaphore **DONE 2025-01-06**
- [x] Tinkex.Future.Combiner **DONE 2025-01-06**
- [x] Tinkex.Files.Types **DONE 2025-01-06**
- [x] Tinkex.Files.Reader **DONE 2025-01-06**
- [x] Tinkex.Files.AsyncReader **DONE 2025-01-06**
- [x] Tinkex.Files.Transform **DONE 2025-01-06**
- [x] Tinkex.Multipart.Encoder **DONE 2025-01-06**
- [x] Tinkex.Multipart.FormSerializer **DONE 2025-01-06**
- [x] Tinkex.Tokenizer.HTTPClient **DONE 2025-01-06**
- [x] Tinkex.CheckpointDownload **DONE 2025-01-06**

---

## Tests

- [x] Core client tests (1245 passing)
- [x] API tests
- [x] Type tests
- [x] Recovery tests
- [x] Telemetry tests
- [x] Reporter sub-module tests (92 tests)
- [x] Regularizer sub-module tests (55 tests)
- [x] Utility module tests (80 tests) **DONE 2025-01-06**
- [x] TrainingClient submodule tests (73 tests) **DONE 2025-01-06**
- [x] SSE streaming tests (24 tests) **DONE 2025-01-06**
- [ ] Additional parity tests with source

---

## Quality Gates

- [x] `mix compile` (passes)
- [x] `mix compile --warnings-as-errors` (passes)
- [x] `mix test` (1702 tinkex tests, 0 failures)
- [x] `mix credo --strict` (no issues)
- [ ] `mix dialyzer`

---

## Priority Implementation Order

### P0 - Current Sprint - COMPLETE

1. [x] TrainingClient: `get_tokenizer/2` **DONE 2025-01-06**
2. [x] TrainingClient: `encode/3` **DONE 2025-01-06**
3. [x] TrainingClient: `decode/3` **DONE 2025-01-06**
4. [x] TrainingClient: `get_info/1` **DONE 2025-01-06**
5. [x] TrainingClient: `unload_model/1` **DONE 2025-01-06**
6. [x] TrainingClient: `forward_backward_custom/4` **DONE 2025-01-06**

### P1 - Next Sprint - ALL COMPLETE

7. [x] CircuitBreaker.Registry **DONE 2025-01-06**
8. [x] Telemetry types (9 modules) **DONE 2025-01-06**
9. [x] API.Telemetry **DONE 2025-01-06**

### P2 - Backlog

10. [x] Telemetry.Provider **DONE 2025-01-06**
11. [x] ServiceClient async wrappers **DONE 2025-01-06**
12. [x] SamplingClient observability **DONE 2025-01-06**
13. [x] RetryConfig **DONE 2025-01-06**

### P3 - Future - ALL COMPLETE

14. [x] Telemetry.Otel **DONE 2025-01-06**
15. [x] RestClient convenience aliases **DONE 2025-01-06**
16. [x] Full Reporter infrastructure **DONE 2025-01-06**
17. [x] Regularizer infrastructure **DONE 2025-01-06**

---

*Last updated: 2025-01-06*
*P0, P1, P2, P3 ALL COMPLETE. Port at ~99% completion with 1702 tests.*
*SSE streaming fully implemented: SSEDecoder, ServerSentEvent with 24 tests.*
*TrainingClient submodules fully implemented: DataProcessor, Observer, Operations, Polling, Tokenizer.*
*API layer fully implemented: URL, Headers, Compression, Helpers, Response, Request, ResponseHandler, StreamResponse, Retry.*
