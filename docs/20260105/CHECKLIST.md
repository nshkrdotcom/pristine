# Implementation Checklist - Tinkex Port

> Auto-maintained by iterative development agents
> Last updated: 2026-01-05 (Iteration 4 Complete)
> **Driver**: Examples from ~/p/g/North-Shore-AI/tinkex/examples/
> **Source**: 179 modules, 75 types, 33 examples, 999 tests across 125 files
> **Port Progress**: 25% complete (45 modules ported)
> **Tests**: 244 passing (up from 189)
> **Next Action**: Implement remaining session types, CustomLossOutput, ModelData

## Legend
- [ ] Not started
- [~] In progress
- [x] Complete
- [!] Blocked

---

## Current Port Status

### Existing (./examples/tinkex/)
**Generated (./examples/tinkex/generated/):**
- [x] Tinkex.Client - Basic generated client
- [x] Tinkex.Sampling resource (create_sample, create_sample_async, create_sample_stream)
- [x] Tinkex.Models resource (list_models, get_model)
- [x] 9 types: ApiError, AsyncSampleResponse, ContentBlock, Model, ModelList, SampleRequest, SampleResult, SampleStreamEvent, Usage

**Manual Implementation (./examples/tinkex/lib/):**
- [x] Tinkex.Config - 22 tests
- [x] Tinkex.Types.ModelInput - 20 tests
- [x] Tinkex.Types.EncodedTextChunk
- [x] Tinkex.Types.ImageChunk
- [x] Tinkex.Types.ImageAssetPointerChunk
- [x] Tinkex.Types.LoraConfig - 7 tests
- [x] Tinkex.Types.AdamParams - 20 tests
- [x] Tinkex.Types.TensorDtype - 10 tests
- [x] Tinkex.Types.TensorData - 14 tests
- [x] Tinkex.Types.Datum - 9 tests

**Total Tests: 102 passing**

### Examples Coverage (2 of 33 = 6%)
- [~] Basic sampling (~60% coverage) - 2 of 5 examples
- [ ] Training workflows (0% coverage) - 0 of 7 examples
- [ ] Checkpoint management (0% coverage) - 0 of 5 examples
- [ ] Session management (0% coverage) - 0 of 2 examples
- [ ] Telemetry & observability (0% coverage) - 0 of 5 examples
- [ ] Recovery (0% coverage) - 0 of 2 examples
- [ ] CLI (0% coverage) - 0 of 3 examples
- [ ] Advanced features (0% coverage) - 0 of 4 examples

---

## Phase 1: Foundation (Enables 60% of examples)

### Infrastructure
- [x] Create `examples/tinkex/lib/` for new modules (coexist with generated/)
- [x] Create `examples/tinkex/test/` for port tests
- [ ] Add mix.exs if standalone project needed (optional)

### Tinkex.Config (Required by ALL examples)
- [x] Config struct with fields: api_key, base_url, timeout, max_retries, user_metadata, tags, telemetry_enabled?
- [x] `new/0` - Create with defaults from env (TINKER_API_KEY)
- [x] `new/1` - Create with explicit options
- [x] Environment variable parsing (TINKER_API_KEY, TINKER_BASE_URL)
- [x] Validation (api_key prefix, timeout, max_retries)
- [x] Python SDK parity mode (:python) and BEAM conservative mode (:beam)
- [x] `mask_api_key/1` for safe logging
- [x] 22 tests passing

### Core Types - Input/Output (20 examples)
- [x] Tinkex.Types.ModelInput (20 tests passing)
  - [x] Struct: chunks list
  - [~] `from_text/2` - Returns error (requires Tokenizer - not yet implemented)
  - [x] `from_ints/1` - Create from token IDs
  - [x] `append/2`, `append_int/2` - Append chunks
  - [x] `to_ints/1` - Convert to token IDs
  - [x] `length/1` - Get token count
  - [x] `empty/0` - Create empty input
- [x] Tinkex.Types.EncodedTextChunk
  - [x] Struct: tokens, type
  - [x] Jason.Encoder implementation
  - [x] `length/1` - Get token count
- [x] Tinkex.Types.ImageChunk
  - [x] Struct: data (base64), format, expected_tokens, type
  - [x] `new/3` - Create from binary
  - [x] `length/1` - Get expected token count
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.ImageAssetPointerChunk
  - [x] Struct: location, format, expected_tokens, type
  - [x] `length/1` - Get expected token count
  - [x] Jason.Encoder implementation

### Core Types - Training (12 examples)
- [x] Tinkex.Types.LoraConfig (7 tests)
  - [x] Struct: rank (32), seed, train_mlp (true), train_attn (true), train_unembed (true)
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.AdamParams (20 tests)
  - [x] Struct: learning_rate (0.0001), beta1 (0.9), beta2 (0.95), eps (1e-12), weight_decay (0.0), grad_clip_norm (0.0)
  - [x] `new/1` - Create with validation
  - [x] Validation: lr > 0, beta1/beta2 in [0,1), eps > 0
- [x] Tinkex.Types.Datum (9 tests)
  - [x] Struct: model_input, loss_fn_inputs
  - [x] `new/1` - Create with TensorData support
  - [~] Nx tensor conversion - Nx not yet a dependency
- [x] Tinkex.Types.TensorData (14 tests)
  - [x] Struct: data, dtype, shape
  - [x] `new/3` - Create from data list
  - [x] `tolist/1` - Get data as list
  - [x] `from_map/1` - Create from decoded JSON
  - [x] Jason.Encoder implementation
  - [~] `to_nx/1`, `from_nx/1` - Nx not yet a dependency
- [x] Tinkex.Types.TensorDtype (10 tests)
  - [x] Type: :int64 | :float32
  - [x] `parse/1`, `to_string/1`, `values/0`, `valid?/1`
  - [~] `from_nx_type/1` - Nx not yet a dependency

### Tinkex.Tokenizer (10 examples)
- [ ] `encode/2` - text, model_name -> [integer]
- [ ] `decode/2` - [integer], model_name -> text
- [ ] Model-specific tokenizer selection
- [ ] Integration with TiktokenEx

### Tinkex.ServiceClient (28 examples)
- [ ] GenServer-based implementation
- [ ] State: config, session_id, telemetry_reporter
- [ ] `start_link/1` - Start with config
- [ ] `create_sampling_client/2` - Create sampling client
- [ ] `create_sampling_client_async/2` - Async variant
- [ ] `create_lora_training_client/3` - Create training client
- [ ] `create_lora_training_client_async/3` - Async variant
- [ ] `create_rest_client/1` - Create REST client
- [ ] `create_training_client_from_state/3` - Restore from checkpoint
- [ ] `create_training_client_from_state_async/3` - Async variant
- [ ] `create_training_client_from_state_with_optimizer/2` - With optimizer state
- [ ] `get_server_capabilities/1` - Get server info
- [ ] `telemetry_reporter/1` - Get telemetry reporter

### Examples Enabled by Phase 1
- [ ] sampling_basic.exs
- [ ] kimi_k2_sampling_live.exs
- [ ] live_capabilities_and_logprobs.exs (partial)
- [ ] llama3_tokenizer_override_live.exs

---

## Phase 2: Training (Enables 80% of examples)

### Tinkex.TrainingClient (12 examples)
- [ ] GenServer-based implementation
- [ ] State: model_id, session_id, seq_id, config
- [ ] `forward/4` - Forward pass only
- [ ] `forward_backward/4` - Forward + backward pass
- [ ] `forward_backward_custom/4` - With custom loss function
- [ ] `optim_step/2` - Apply optimizer step
- [ ] `save_state/2` - Save checkpoint with optimizer state
- [ ] `load_state/2` - Load checkpoint
- [ ] `load_state_with_optimizer/2` - Load with optimizer state
- [ ] `save_weights_for_sampler/2` - Save for sampling
- [ ] `save_weights_and_get_sampling_client_sync/1` - Save + create sampler
- [ ] `unload_model/1` - Unload from GPU
- [ ] Nested: DataProcessor.chunk_data/1

### Training Types
- [x] Tinkex.Types.ForwardBackwardInput (29 tests for training types)
  - [x] Struct: data [Datum], loss_fn, loss_fn_config
  - [x] Jason.Encoder (converts atom to string)
- [x] Tinkex.Types.ForwardBackwardRequest
  - [x] Struct: forward_backward_input, model_id, seq_id
  - [x] Jason.Encoder
- [x] Tinkex.Types.ForwardBackwardOutput
  - [x] Struct: loss_fn_output_type, loss_fn_outputs, metrics
  - [x] `from_json/1`, `loss/1`
- [x] Tinkex.Types.ForwardRequest
  - [x] Struct: forward_input, model_id, seq_id
  - [x] Jason.Encoder
- [x] Tinkex.Types.OptimStepRequest
  - [x] Struct: adam_params, model_id, seq_id
  - [x] Jason.Encoder
- [x] Tinkex.Types.OptimStepResponse
  - [x] Struct: metrics
  - [x] `from_json/1`, `success?/1`
- [x] Tinkex.Types.LossFnType
  - [x] Type: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro
  - [x] `parse/1`, `to_string/1`, `values/0`
- [ ] Tinkex.Types.CustomLossOutput
  - [ ] Struct: loss_total, base_loss, regularizers, regularizer_total, total_grad_norm
  - [ ] `build/4`, `loss/1`

### Checkpoint Types (55 tests for weight/checkpoint types)
- [x] Tinkex.Types.Cursor
  - [x] Struct: offset, limit, total_count
  - [x] `from_map/1` with integer coercion
- [x] Tinkex.Types.Checkpoint
  - [x] Struct: checkpoint_id, checkpoint_type, tinker_path, training_run_id, size_bytes, public, time
  - [x] `from_map/1` with datetime parsing
  - [x] `training_run_from_path/1`
- [x] Tinkex.Types.CheckpointsListResponse
  - [x] Struct: checkpoints, cursor
  - [x] `from_map/1`
- [x] Tinkex.Types.ParsedCheckpointTinkerPath
  - [x] Struct: tinker_path, training_run_id, checkpoint_type, checkpoint_id
  - [x] `from_tinker_path/1` - Parse tinker:// URIs
  - [x] `checkpoint_segment/1` - Convert to REST path
- [x] Tinkex.Types.SaveWeightsRequest
  - [x] Struct: model_id, path, seq_id, type
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.SaveWeightsResponse
  - [x] Struct: path, type
  - [x] `from_json/1`
- [x] Tinkex.Types.SaveWeightsForSamplerRequest
  - [x] Struct: model_id, path, sampling_session_seq_id, seq_id, type
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.SaveWeightsForSamplerResponse
  - [x] Struct: path, sampling_session_id, type
  - [x] `from_json/1`
- [x] Tinkex.Types.LoadWeightsRequest
  - [x] Struct: model_id, path, seq_id, optimizer, type
  - [x] `new/2`, `new/3` helper functions
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.LoadWeightsResponse
  - [x] Struct: path, type
  - [x] `from_json/1`

### Sampling Types (Extended)
- [ ] Tinkex.Types.SamplingParams
  - [ ] Struct: max_tokens, seed, stop, temperature (1.0), top_k (-1), top_p (1.0)
- [ ] Tinkex.Types.SampledSequence
  - [ ] Struct: tokens, logprobs, stop_reason
  - [ ] `from_json/1`
- [ ] Tinkex.Types.StopReason
  - [ ] Type: :length | :stop
  - [ ] `parse/1`, `to_string/1`
- [ ] Tinkex.Types.SampleRequest (extended)
  - [ ] Add: num_samples, prompt_logprobs (tri-state), topk_prompt_logprobs
- [ ] Tinkex.Types.SampleResponse (extended)
  - [ ] Struct: sequences, prompt_logprobs, topk_prompt_logprobs, type
- [ ] Tinkex.Types.SampleStreamChunk (extended)
  - [ ] Add: event_type (:token | :done | :error), finish_reason, total_tokens

### Examples Enabled by Phase 2
- [ ] training_loop.exs
- [ ] adam_and_chunking_live.exs
- [ ] forward_inference.exs
- [ ] custom_loss_training.exs
- [ ] save_weights_and_sample.exs
- [ ] training_persistence_live.exs (partial)

---

## Phase 3: REST & Sessions (Enables 90% of examples)

### Tinkex.RestClient (8 examples)
- [ ] GenServer or struct-based implementation
- [ ] State: config, session_id
- [ ] `list_sessions/2` - List active sessions
- [ ] `get_session/2` - Get session details
- [ ] `list_user_checkpoints/2` - List user's checkpoints with pagination
- [ ] `list_checkpoints/2` - List checkpoints for run_id
- [ ] `get_checkpoint_archive_url/2` - Get download URL
- [ ] `delete_checkpoint/2` - Delete checkpoint

### Tinkex.SamplingClient (Extended) (15 examples)
- [ ] `sample/4` with queue_state_observer option
- [ ] `compute_logprobs/2` - Compute log probabilities

### Session Types
- [x] Tinkex.Types.CreateSessionRequest (24 tests total for session types)
  - [x] Struct: tags, user_metadata, sdk_version, type
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.CreateSessionResponse
  - [x] Struct: session_id, info_message, warning_message, error_message
  - [x] `from_json/1`
- [x] Tinkex.Types.CreateSamplingSessionRequest
  - [x] Struct: session_id, sampling_session_seq_id, base_model, model_path, type
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.CreateSamplingSessionResponse
  - [x] Struct: sampling_session_id
  - [x] `from_json/1`
- [x] Tinkex.Types.SessionHeartbeatRequest
  - [x] Struct: session_id, type
  - [x] `new/1`, `to_json/1`, `from_json/1`
- [x] Tinkex.Types.SessionHeartbeatResponse
  - [x] Struct: type
  - [x] `new/0`, `from_json/1`
- [ ] Tinkex.Types.ListSessionsResponse
  - [ ] Struct: sessions [String]
- [ ] Tinkex.Types.GetSessionResponse
  - [ ] Struct: training_run_ids, sampler_ids

### Model Types
- [x] Tinkex.Types.CreateModelRequest
  - [x] Struct: session_id, model_seq_id, base_model, user_metadata, lora_config, type
  - [x] Jason.Encoder implementation
  - [x] Default lora_config: %LoraConfig{}
- [x] Tinkex.Types.CreateModelResponse
  - [x] Struct: model_id
  - [x] `from_json/1`
- [x] Tinkex.Types.GetInfoRequest
  - [x] Struct: model_id, type
  - [x] `new/1`
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.GetInfoResponse
  - [x] Struct: model_id, model_data, is_lora, lora_rank, model_name, type
  - [x] `from_json/1` (handles string and atom keys)
- [ ] Tinkex.Types.ModelData
  - [ ] Struct: arch, model_name, tokenizer_id
- [ ] Tinkex.Types.UnloadModelRequest
  - [ ] Struct: model_id, type
  - [ ] `new/1`
- [ ] Tinkex.Types.UnloadModelResponse
  - [ ] Struct: model_id, type
- [ ] Tinkex.Types.GetSamplerResponse
  - [ ] Struct: sampler_id, base_model, model_path

### Training Run Types
- [ ] Tinkex.Types.TrainingRun
  - [ ] Struct: training_run_id, base_model, model_owner, is_lora, lora_rank, corrupted, last_request_time, last_checkpoint, last_sampler_checkpoint, user_metadata
  - [ ] `from_map/1` with datetime parsing
- [ ] Tinkex.Types.TrainingRunsResponse
  - [ ] Struct: training_runs, cursor
- [ ] Tinkex.Types.WeightsInfoResponse
  - [ ] Struct: base_model, is_lora, lora_rank
- [ ] Tinkex.Types.Cursor
  - [ ] Struct: offset, limit, total_count
  - [ ] `from_map/1`

### Future & Async Types
- [ ] Tinkex.Types.FutureRetrieveRequest
  - [ ] Struct: request_id
  - [ ] `new/1`, `to_json/1`
- [ ] Tinkex.Types.FuturePendingResponse
  - [ ] Struct: status "pending"
- [ ] Tinkex.Types.FutureCompletedResponse
  - [ ] Struct: status "completed", result
- [ ] Tinkex.Types.FutureFailedResponse
  - [ ] Struct: status "failed", error
- [ ] Tinkex.Types.FutureRetrieveResponse (union type)
  - [ ] `from_json/1` with type detection
- [ ] Tinkex.Types.TryAgainResponse
  - [ ] Struct: type, request_id, queue_state, retry_after_ms, queue_state_reason
  - [ ] `from_map/1` with validation
- [ ] Tinkex.Types.QueueState
  - [ ] Type: :active | :paused_rate_limit | :paused_capacity | :unknown
  - [ ] `parse/1`

### Server Types
- [ ] Tinkex.Types.HealthResponse
  - [ ] Struct: status
- [ ] Tinkex.Types.GetServerCapabilitiesResponse
  - [ ] Struct: supported_models
  - [ ] `from_json/1`, `model_names/1`
- [ ] Tinkex.Types.SupportedModel
  - [ ] Struct: model_id, model_name, arch
  - [ ] `from_json/1` with backward compat

### API Layer Modules
- [ ] Tinkex.API.Session
  - [ ] `create/2`, `create_typed/2`
- [ ] Tinkex.API.Service
  - [ ] `create_model/2`, `get_server_capabilities/2`, `health_check/2`
- [ ] Tinkex.API.Models
  - [ ] `get_info/2`, `unload_model/2`
- [ ] Tinkex.API.Futures
  - [ ] `retrieve/2`
- [ ] Tinkex.API.Rest
  - [ ] `list_training_runs/3`, `get_training_run/2`

### Examples Enabled by Phase 3
- [ ] checkpoints_management.exs
- [ ] sessions_management.exs
- [ ] heartbeat_probe.exs
- [ ] async_client_creation.exs
- [ ] model_info_and_unload.exs
- [ ] weights_inspection.exs

---

## Phase 4: Telemetry & Resilience (Enables 95% of examples)

### Tinkex.Telemetry.Reporter (4 examples)
- [ ] GenServer-based implementation
- [ ] State: session_id, config, queue, flush settings
- [ ] `start_link/1` - Start with config
- [ ] `log/3` - Log event with data
- [ ] `log/4` - Log event with severity
- [ ] `log_exception/3` - Log exception with severity
- [ ] `flush/2` - Flush queue (sync?, wait_drained?)
- [ ] `wait_until_drained/2` - Wait for queue drain
- [ ] `stop/2` - Graceful shutdown

### Tinkex.Telemetry (3 examples)
- [ ] `attach_logger/1` - Attach telemetry logger
- [ ] `detach/1` - Detach handler

### Tinkex.Metrics (1 example)
- [ ] ETS-based implementation
- [ ] `reset/0` - Reset all metrics
- [ ] `flush/0` - Flush metrics
- [ ] `snapshot/0` - Get current snapshot (p50, p95, p99)

### Tinkex.Retry (2 examples)
- [ ] Integration with Foundation.Retry
- [ ] `with_retry/2` - Execute with retry

### Tinkex.RetryHandler (2 examples)
- [ ] `new/1` - Create handler with base_delay_ms, jitter_pct, max_retries

### Tinkex.Telemetry.Capture (1 example)
- [ ] `capture_exceptions/2` - Capture and log exceptions

### Tinkex.Recovery (2 examples)
- [ ] Tinkex.Recovery.Policy
  - [ ] `new/1` - Create policy with enabled, checkpoint_strategy, poll_interval_ms, etc.
- [ ] Tinkex.Recovery.Executor
  - [ ] `start_link/1` - Start with max_concurrent
- [ ] Tinkex.Recovery.Monitor
  - [ ] `start_link/1` - Start with policy, executor
  - [ ] `monitor_run/4` - Monitor training run

### Error Types
- [ ] Tinkex.Types.RequestErrorCategory
  - [ ] Type: :unknown | :server | :user
  - [ ] `parse/1`, `to_string/1`, `retryable?/1`
- [ ] Tinkex.Types.RequestFailedResponse
  - [ ] Struct: error, category
  - [ ] `new/2`, `from_json/1`
- [ ] Tinkex.Error
  - [ ] Struct: type, message, status_code
  - [ ] Pattern matching helpers

### Examples Enabled by Phase 4
- [ ] telemetry_reporter_demo.exs
- [ ] telemetry_live.exs
- [ ] metrics_live.exs
- [ ] retry_and_capture.exs
- [ ] recovery_simulated.exs
- [ ] recovery_live_injected.exs

---

## Phase 5: Advanced Features (Enables 100% of examples)

### Tinkex.Regularizer (2 examples)
- [ ] Tinkex.Regularizer.Pipeline
  - [ ] `compute/4` - Compute with regularizers
- [ ] Tinkex.Regularizer.Executor
  - [ ] `execute_one/4`, `execute_all/4`
- [ ] Tinkex.Regularizer.GradientTracker
  - [ ] `compute_grad_norm/2`
- [ ] Tinkex.Regularizer.Telemetry
  - [ ] `attach_logger/1`

### Tinkex.Regularizers.* (2 examples)
- [ ] L1.compute/3
- [ ] L2.compute/3
- [ ] ElasticNet.compute/3
- [ ] Entropy.compute/3
- [ ] KLDivergence.compute/3
- [ ] Consistency.compute/3
- [ ] Orthogonality.compute/3
- [ ] GradientPenalty.compute/3

### Regularizer Types
- [ ] Tinkex.Types.RegularizerSpec
  - [ ] Struct: fn, weight, name, async
  - [ ] `new/1` with validation
- [ ] Tinkex.Types.RegularizerOutput
  - [ ] Struct: name, value, weight, contribution, grad_norm, grad_norm_weighted, custom
  - [ ] `from_computation/5`

### Tinkex.CLI (3 examples)
- [ ] `run/1` - Execute CLI commands
- [ ] Command parsing
- [ ] Commands: run, checkpoint, version

### Tinkex.CheckpointDownload (1 example)
- [ ] `download/3` - Download and extract checkpoint archives
- [ ] Progress callback support
- [ ] Retry logic for archive availability

### Queue & Dispatch (2 examples)
- [ ] Tinkex.QueueStateLogger
  - [ ] `log_state_change/4`
- [ ] Tinkex.SamplingDispatch
  - [ ] `set_backoff/2`
  - [ ] `with_rate_limit/3`
- [ ] Tinkex.ByteEstimator
  - [ ] `estimate_model_input_bytes/1`
- [ ] QueueStateObserver behaviour

### Multipart (1 example)
- [ ] Tinkex.Files.Transform
  - [ ] `transform_files/1`
- [ ] Tinkex.Multipart.Encoder
  - [ ] `encode_multipart/2`
- [ ] Tinkex.Multipart.FormSerializer
  - [ ] `serialize_form_fields/1`

### Examples Enabled by Phase 5
- [ ] structured_regularizers.exs
- [ ] structured_regularizers_live.exs
- [ ] cli_run_text.exs
- [ ] cli_run_prompt_file.exs
- [ ] checkpoint_multi_delete_live.exs
- [ ] checkpoint_download.exs
- [ ] queue_reasons_and_sampling_throttling.exs
- [ ] queue_state_observer_demo.exs
- [ ] file_upload_multipart.exs
- [ ] multimodal_resume_and_cleanup.exs

---

## Quality Gates

### Per-Phase Gates
- [ ] Phase compiles without warnings
- [ ] Phase tests pass
- [ ] Phase examples run successfully

### Final Gates
- [ ] `mix compile --warnings-as-errors` - Zero warnings
- [ ] `mix test` - All tests passing
- [ ] `mix dialyzer` - Zero errors
- [ ] `mix credo --strict` - Zero issues
- [ ] All 33 source examples work with port

---

## Completion Criteria

- [ ] All 75 types implemented with Sinter validation
- [ ] All 4 core clients implemented (ServiceClient, TrainingClient, SamplingClient, RestClient)
- [ ] All API modules implemented
- [ ] Telemetry & recovery infrastructure complete
- [ ] Regularizer system complete
- [ ] CLI functional
- [ ] **All 33 source examples execute successfully**
