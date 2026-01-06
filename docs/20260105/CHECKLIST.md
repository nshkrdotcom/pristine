# Implementation Checklist - Tinkex Port

> Auto-maintained by iterative development agents
> Last updated: 2026-01-05 (Iteration 17 Complete)
> **Driver**: Examples from ~/p/g/North-Shore-AI/tinkex/examples/
> **Source**: 179 modules, 75 types, 33 examples, 999 tests across 125 files
> **Port Progress**: 61% complete (109 modules ported)
> **Tests**: 926 passing (20 new in iteration 17)
> **Next Action**: Implement streaming support, add SSE integration

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
- [x] 9 types: ApiError, ApiSampleRequest, AsyncSampleResponse, ContentBlock, Model, ModelList, SampleResult, SampleStreamEvent, Usage

**Manual Implementation (./examples/tinkex/lib/):**
- [x] Tinkex (main module) - 9 tests
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

### Tinkex.Tokenizer (10 examples) - 23 tests
- [x] `encode/3` - text, model_name, opts -> {:ok, [integer]} | {:error, Error.t()}
- [x] `decode/3` - [integer], model_name, opts -> {:ok, String.t()} | {:error, Error.t()}
- [x] `get_tokenizer_id/3` - Model-specific tokenizer resolution (Llama-3 workaround, variant stripping)
- [x] `get_or_load_tokenizer/2` - ETS-cached tokenizer loading
- [x] `kimi_tokenizer?/1` - Kimi tokenizer detection
- [x] Integration with TiktokenEx for Kimi K2 tokenizers
- [x] HuggingFace file download for Kimi tokenizers (tiktoken.model, tokenizer_config.json)

### Tinkex.ServiceClient (Scaffolding) (12 tests)
- [x] Struct-based implementation with session management
- [x] `new/2` - Create with config, auto-creates session
- [x] `create_sampling_client/2` - Create sampling client
- [x] `create_lora_training_client/4` - Create training client
- [x] `create_rest_client/1` - Create REST client
- [x] `create_training_client_from_state/4` - Restore from checkpoint
- [x] `get_server_capabilities/1` - Get server info
- [x] `session_id/1`, `config/1` - Accessors
- [x] `next_training_seq_id/1`, `next_sampling_seq_id/1` - Sequence IDs
- [ ] Async variants (`*_async`) (future)
- [ ] GenServer-based implementation (future)
- [ ] Telemetry reporter integration (future)

### Examples Enabled by Phase 1
- [ ] sampling_basic.exs
- [ ] kimi_k2_sampling_live.exs
- [ ] live_capabilities_and_logprobs.exs (partial)
- [ ] llama3_tokenizer_override_live.exs

---

## Phase 2: Training (Enables 80% of examples)

### Tinkex.TrainingClient (Scaffolding) (12 tests)
- [x] Struct-based client with model_id, session_id, config
- [x] `forward/3` - Forward pass only
- [x] `forward_backward/4` - Forward + backward pass
- [x] `optim_step/3` - Apply optimizer step
- [x] `save_state/3` - Save checkpoint with optional optimizer state
- [x] `load_state/3` - Load checkpoint
- [x] `save_weights_for_sampler/3` - Save for sampling
- [x] `next_seq_id/1` - Atomic sequence ID generation
- [x] `parse_forward_backward_response/1` - Response parsing
- [ ] `forward_backward_custom/4` - With custom loss function (future)
- [ ] `unload_model/1` - Unload from GPU (future)
- [ ] DataProcessor.chunk_data/1 (future)

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
- [x] Tinkex.Types.CustomLossOutput
  - [x] Struct: loss_total, base_loss, regularizers, regularizer_total, total_grad_norm
  - [x] `build/4`, `loss/1`
  - [x] Jason.Encoder implementation

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

### Sampling Types (Extended) - 74 tests for sampling/future/server types
- [x] Tinkex.Types.SamplingParams
  - [x] Struct: max_tokens, seed, stop, temperature (1.0), top_k (-1), top_p (1.0)
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.SampledSequence
  - [x] Struct: tokens, logprobs, stop_reason
  - [x] `from_json/1`
- [x] Tinkex.Types.StopReason
  - [x] Type: :length | :stop
  - [x] `parse/1`, `to_string/1`
- [x] Tinkex.Types.SampleRequest (8 tests)
  - [x] Struct: sampling_session_id, seq_id, base_model, model_path, prompt, sampling_params
  - [x] Add: num_samples, prompt_logprobs (tri-state), topk_prompt_logprobs
  - [x] Jason.Encoder with tri-state prompt_logprobs handling
- [x] Tinkex.Types.SampleResponse (7 tests)
  - [x] Struct: sequences, prompt_logprobs, topk_prompt_logprobs, type
  - [x] `from_json/1` with topk parsing from tuples/lists/maps
- [x] Tinkex.Types.SampleStreamChunk (12 tests)
  - [x] Struct: token, token_id, index, finish_reason, total_tokens, logprob
  - [x] Add: event_type (:token | :done | :error)
  - [x] `from_map/1`, `done/2`, `error/1`, `done?/1`
  - [x] Jason.Encoder implementation

### Examples Enabled by Phase 2
- [ ] training_loop.exs
- [ ] adam_and_chunking_live.exs
- [ ] forward_inference.exs
- [ ] custom_loss_training.exs
- [ ] save_weights_and_sample.exs
- [ ] training_persistence_live.exs (partial)

---

## Phase 3: REST & Sessions (Enables 90% of examples)

### Tinkex.RestClient (8 examples) - 21 tests
- [x] Struct-based implementation with session_id and config
- [x] `list_sessions/2` - List active sessions with pagination
- [x] `get_session/2` - Get session details
- [x] `list_user_checkpoints/2` - List user's checkpoints with pagination
- [x] `list_checkpoints/2` - List checkpoints for run_id
- [x] `get_checkpoint_archive_url/2` - Get download URL (both tinker path and IDs)
- [x] `delete_checkpoint/2` - Delete checkpoint (both tinker path and IDs)
- [x] `publish_checkpoint/2`, `unpublish_checkpoint/2` - Visibility management
- [x] `get_training_run/2`, `get_training_run_by_tinker_path/2` - Training run info
- [x] `list_training_runs/2` - List training runs with pagination
- [x] `get_sampler/2`, `get_weights_info_by_tinker_path/2` - Sampler/weights info
- [x] Async variants for all operations (`*_async`)

### Tinkex.SamplingClient (Scaffolding) (13 tests)
- [x] Struct-based client with session_id and config
- [x] `sample/4` with queue_state_observer option
- [x] `sample_stream/4` - Streaming sample generation
- [x] `compute_logprobs/3` - Compute log probabilities
- [x] `next_seq_id/1` - Atomic sequence ID generation
- [x] `parse_sample_response/1` - Response parsing

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
- [x] Tinkex.Types.ListSessionsResponse
  - [x] Struct: sessions [String]
  - [x] `from_map/1`
- [x] Tinkex.Types.GetSessionResponse
  - [x] Struct: training_run_ids, sampler_ids
  - [x] `from_map/1`

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
- [x] Tinkex.Types.ModelData
  - [x] Struct: arch, model_name, tokenizer_id
  - [x] `from_json/1`
- [x] Tinkex.Types.UnloadModelRequest
  - [x] Struct: model_id, type
  - [x] `new/1`
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.UnloadModelResponse
  - [x] Struct: model_id, type
  - [x] `from_json/1`
- [x] Tinkex.Types.GetSamplerResponse
  - [x] Struct: sampler_id, base_model, model_path
  - [x] `from_json/1`
  - [x] Jason.Encoder implementation

### Training Run Types (45 tests for session/model/training types)
- [x] Tinkex.Types.TrainingRun
  - [x] Struct: training_run_id, base_model, model_owner, is_lora, lora_rank, corrupted, last_request_time, last_checkpoint, last_sampler_checkpoint, user_metadata
  - [x] `from_map/1` with datetime parsing and nested Checkpoint parsing
- [x] Tinkex.Types.TrainingRunsResponse
  - [x] Struct: training_runs, cursor
  - [x] `from_map/1` with TrainingRun and Cursor parsing
- [x] Tinkex.Types.WeightsInfoResponse
  - [x] Struct: base_model, is_lora, lora_rank
  - [x] `from_json/1`
  - [x] Jason.Encoder implementation

### Future & Async Types
- [x] Tinkex.Types.FutureRetrieveRequest
  - [x] Struct: request_id
  - [x] `new/1`, `to_json/1`, `from_json/1`
- [x] Tinkex.Types.FuturePendingResponse
  - [x] Struct: status "pending"
- [x] Tinkex.Types.FutureCompletedResponse
  - [x] Struct: status "completed", result
- [x] Tinkex.Types.FutureFailedResponse
  - [x] Struct: status "failed", error
- [x] Tinkex.Types.FutureRetrieveResponse (union type)
  - [x] `from_json/1` with type detection
- [x] Tinkex.Types.TryAgainResponse
  - [x] Struct: type, request_id, queue_state, retry_after_ms, queue_state_reason
  - [x] `from_map/1` with validation
- [x] Tinkex.Types.QueueState
  - [x] Type: :active | :paused_rate_limit | :paused_capacity | :unknown
  - [x] `parse/1`, `to_string/1`

### Server Types
- [x] Tinkex.Types.HealthResponse
  - [x] Struct: status
  - [x] `from_json/1`
- [x] Tinkex.Types.GetServerCapabilitiesResponse
  - [x] Struct: supported_models
  - [x] `from_json/1`, `model_names/1`
- [x] Tinkex.Types.SupportedModel
  - [x] Struct: model_id, model_name, arch
  - [x] `from_json/1` with backward compat (string support)

### API Layer Modules (27 tests)
- [x] Tinkex.HTTPClient behaviour
  - [x] `post/3`, `get/2`, `delete/2` callbacks
- [x] Tinkex.API (base module)
  - [x] `client_module/1` - Resolve HTTP client
  - [x] Default stub implementations
- [x] Tinkex.API.Session
  - [x] `create/2`, `create_typed/2`, `heartbeat/2`
- [x] Tinkex.API.Service
  - [x] `create_model/2`, `create_sampling_session/2`
  - [x] `get_server_capabilities/1`, `health_check/1`
- [x] Tinkex.API.Models
  - [x] `get_info/2`, `unload_model/2`
- [x] Tinkex.API.Futures
  - [x] `retrieve/2`
- [x] Tinkex.API.Training
  - [x] `forward_backward_future/2`, `optim_step_future/2`, `forward_future/2`
- [x] Tinkex.API.Rest (22 tests)
  - [x] `list_training_runs/3`, `get_training_run/2`
  - [x] `list_sessions/3`, `get_session/2`
  - [x] `list_checkpoints/2`, `list_user_checkpoints/3`
  - [x] `get_checkpoint_archive_url/2`, `delete_checkpoint/2`
  - [x] `get_sampler/2`, `get_weights_info_by_tinker_path/2`
  - [x] `publish_checkpoint/2`, `unpublish_checkpoint/2`

### Tinkex.HuggingFace (8 tests)
- [x] `resolve_file/4` - Download and cache files from HuggingFace
- [x] `build_hf_url/3` - Build HuggingFace download URL
- [x] `sanitize_repo_id/1` - Sanitize repo ID for filesystem
- [x] `default_cache_dir/0` - Default cache directory

### Future Polling (19 tests)
- [x] Tinkex.Future
  - [x] `poll/2` - Start polling task for server-side future
  - [x] `await/2` - Wait for polling task result
  - [x] `await_many/2` - Wait for multiple tasks
  - [x] State machine: pending, completed, failed, try_again handling
  - [x] Exponential backoff (configurable)
  - [x] Queue state telemetry events
  - [x] QueueStateObserver callbacks
  - [x] HTTP error retry logic (408, 5xx, connection errors)
  - [x] Poll timeout handling

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

### Error Types (23 tests)
- [x] Tinkex.Types.RequestErrorCategory
  - [x] Type: :unknown | :server | :user
  - [x] `parse/1`, `to_string/1`, `retryable?/1`
- [x] Tinkex.Types.RequestFailedResponse
  - [x] Struct: error, category
  - [x] `new/2`, `from_json/1`
- [x] Tinkex.Error
  - [x] Struct: type, message, status, category, data, retry_after_ms
  - [x] `new/2`, `new/3`, `from_response/2`
  - [x] `user_error?/1`, `retryable?/1`, `format/1`
  - [x] String.Chars implementation

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

### Regularizer Types (20 tests)
- [x] Tinkex.Types.RegularizerSpec
  - [x] Struct: fn, weight, name, async
  - [x] `new/1` with validation
  - [x] `validate!/1` - Validates fn arity, weight, name, async
- [x] Tinkex.Types.RegularizerOutput
  - [x] Struct: name, value, weight, contribution, grad_norm, grad_norm_weighted, custom
  - [x] `from_computation/5`
  - [x] Jason.Encoder implementation
- [x] Tinkex.Types.TelemetryResponse
  - [x] Struct: status
  - [x] `new/0`, `from_json/1`
- [x] Tinkex.Types.TypeAliases
  - [x] Type definitions: model_input_chunk, loss_fn_inputs, loss_fn_output

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
