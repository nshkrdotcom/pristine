# Tinkex Resource Modules and Endpoints Analysis

## Overview

The Tinker SDK defines 7 resource modules with a total of 20 endpoints. All endpoints follow an async pattern (AsyncResource classes) and use HTTP POST/GET/DELETE methods with JSON request/response bodies. The architecture emphasizes idempotency through idempotency_key support and async/future-based result retrieval for long-running operations.

---

## 1. SERVICE RESOURCE (AsyncServiceResource)

**Module**: `/tinker/resources/service.py`

### 1.1 get_server_capabilities
- **HTTP Method**: GET
- **Path**: `/api/v1/get_server_capabilities`
- **Request**: None (no body)
- **Response**: `GetServerCapabilitiesResponse`
- **Idempotency**: No
- **Description**: Retrieves information about supported models and server capabilities

### 1.2 health_check
- **HTTP Method**: GET
- **Path**: `/api/v1/healthz`
- **Request**: None (no body)
- **Response**: `HealthResponse`
- **Idempotency**: No
- **Description**: Checks if the API server is ready

### 1.3 create_session
- **HTTP Method**: POST
- **Path**: `/api/v1/create_session`
- **Request Type**: `CreateSessionRequest`
- **Request Fields**:
  - `tags: list[str]`
  - `user_metadata: dict[str, Any] | None`
  - `sdk_version: str`
  - `type: Literal["create_session"]`
- **Response**: `CreateSessionResponse`
- **Idempotency**: Yes
- **Description**: Creates a new session for managing training and sampling operations

### 1.4 session_heartbeat
- **HTTP Method**: POST
- **Path**: `/api/v1/session_heartbeat`
- **Request Type**: `SessionHeartbeatRequest`
- **Request Fields**:
  - `session_id: str`
- **Response**: `SessionHeartbeatResponse`
- **Idempotency**: No
- **Description**: Send a heartbeat for an active session to keep it alive

### 1.5 create_sampling_session
- **HTTP Method**: POST
- **Path**: `/api/v1/create_sampling_session`
- **Request Type**: `CreateSamplingSessionRequest`
- **Request Fields**:
  - `session_id: str` (required)
  - `sampling_session_seq_id: int` (required)
  - `base_model: Optional[str]`
  - `model_path: Optional[str]` (tinker:// URI)
  - `type: Literal["create_sampling_session"]`
- **Response**: `CreateSamplingSessionResponse`
- **Idempotency**: No
- **Description**: Creates a new sampling session for multi-turn inference

---

## 2. MODELS RESOURCE (AsyncModelsResource)

**Module**: `/tinker/resources/models.py`

### 2.1 create
- **HTTP Method**: POST
- **Path**: `/api/v1/create_model`
- **Request Type**: `CreateModelRequest`
- **Request Fields**:
  - `session_id: str` (required)
  - `model_seq_id: int` (required)
  - `base_model: str` (required)
  - `user_metadata: Optional[dict[str, Any]]`
  - `lora_config: Optional[LoraConfig]`
  - `type: Literal["create_model"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Special**: Returns async future for long-running operation
- **Description**: Creates a new model with optional LoRA fine-tuning configuration

### 2.2 get_info
- **HTTP Method**: POST
- **Path**: `/api/v1/get_info`
- **Request Type**: `GetInfoRequest`
- **Request Fields**:
  - `model_id: ModelID` (required)
  - `type: Literal["get_info"]`
- **Response Type**: `GetInfoResponse`
- **Idempotency**: Yes
- **Description**: Retrieves metadata information about a specific model

### 2.3 unload
- **HTTP Method**: POST
- **Path**: `/api/v1/unload_model`
- **Request Type**: `UnloadModelRequest`
- **Request Fields**:
  - `model_id: ModelID` (required)
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Special**: Returns async future for long-running operation
- **Description**: Unload model weights and ends the user's session

---

## 3. WEIGHTS RESOURCE (AsyncWeightsResource)

**Module**: `/tinker/resources/weights.py`

### 3.1 load
- **HTTP Method**: POST
- **Path**: `/api/v1/load_weights`
- **Request Type**: `LoadWeightsRequest`
- **Request Fields**:
  - `model_id: ModelID` (required)
  - `path: str` (required) - tinker:// URI
  - `optimizer: bool` (required)
  - `seq_id: Optional[int]`
  - `type: Literal["load_weights"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Loads model weights from disk at specific checkpoint step

### 3.2 save
- **HTTP Method**: POST
- **Path**: `/api/v1/save_weights`
- **Request Type**: `SaveWeightsRequest`
- **Request Fields**:
  - `model_id: ModelID` (required)
  - `path: Optional[str]`
  - `seq_id: Optional[int]`
  - `type: Literal["save_weights"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Saves model weights to disk

### 3.3 save_for_sampler
- **HTTP Method**: POST
- **Path**: `/api/v1/save_weights_for_sampler`
- **Request Type**: `SaveWeightsForSamplerRequest`
- **Request Fields**:
  - `model_id: ModelID` (required)
  - `path: Optional[str]`
  - `seq_id: Optional[int]`
  - `type: Literal["save_weights_for_sampler"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Saves model weights optimized for sampler operations

### 3.4 list
- **HTTP Method**: GET
- **Path**: `/api/v1/training_runs/{model_id}/checkpoints`
- **Request**: Path parameter `model_id: ModelID`
- **Response Type**: `CheckpointsListResponse`
- **Idempotency**: No
- **Description**: Lists all available model checkpoints (training and sampler)

### 3.5 delete_checkpoint
- **HTTP Method**: DELETE
- **Path**: `/api/v1/training_runs/{model_id}/checkpoints/{checkpoint_id}`
- **Request**: Path parameters (model_id, checkpoint_id)
- **Response**: `None`
- **Idempotency**: No
- **Description**: Delete a checkpoint for the given training run

### 3.6 get_checkpoint_archive_url
- **HTTP Method**: GET
- **Path**: `/api/v1/training_runs/{model_id}/checkpoints/{checkpoint_id}/archive`
- **Request**: Path parameters (model_id, checkpoint_id)
- **Response Type**: `CheckpointArchiveUrlResponse`
- **Special Handling**:
  - Expects 302 redirect response
  - Extracts Location header for signed URL
  - Sets follow_redirects=False
  - Sets Accept header to "application/gzip"
- **Description**: Get signed URL to download checkpoint archive as gzip

---

## 4. TRAINING RESOURCE (AsyncTrainingResource)

**Module**: `/tinker/resources/training.py`

### 4.1 forward
- **HTTP Method**: POST
- **Path**: `/api/v1/forward`
- **Request Type**: `ForwardRequest`
- **Request Fields**:
  - `forward_input: ForwardBackwardInput` (required)
  - `model_id: ModelID` (required)
  - `seq_id: Optional[int]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Performs a forward pass through the model

### 4.2 forward_backward
- **HTTP Method**: POST
- **Path**: `/api/v1/forward_backward`
- **Request Type**: `ForwardBackwardRequest`
- **Request Fields**:
  - `forward_backward_input: ForwardBackwardInput` (required)
  - `model_id: ModelID` (required)
  - `seq_id: Optional[int]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Performs forward and backward pass (gradient computation)

### 4.3 optim_step
- **HTTP Method**: POST
- **Path**: `/api/v1/optim_step`
- **Request Type**: `OptimStepRequest`
- **Request Fields**:
  - `adam_params: AdamParams` (required)
    - `learning_rate: float = 0.0001`
    - `beta1: float = 0.9`
    - `beta2: float = 0.95`
    - `eps: float = 1e-12`
    - `weight_decay: float = 0.0`
    - `grad_clip_norm: float = 0.0`
  - `model_id: ModelID` (required)
  - `seq_id: Optional[int]`
  - `type: Literal["optim_step"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Description**: Performs an optimization step to update model parameters

---

## 5. SAMPLING RESOURCE (AsyncSamplingResource)

**Module**: `/tinker/resources/sampling.py`

### 5.1 asample
- **HTTP Method**: POST
- **Path**: `/api/v1/asample`
- **Request Type**: `SampleRequest`
- **Request Fields**:
  - `prompt: ModelInput` (required)
  - `sampling_params: SamplingParams` (required)
  - `num_samples: int = 1`
  - `base_model: Optional[str]`
  - `model_path: Optional[str]` (tinker:// URI)
  - `sampling_session_id: Optional[str]`
  - `seq_id: Optional[int]`
  - `prompt_logprobs: Optional[bool]`
  - `topk_prompt_logprobs: int = 0`
  - `type: Literal["sample"]`
- **Response Type**: `UntypedAPIFuture`
- **Idempotency**: Yes
- **Special**:
  - Supports deterministic request IDs via seq_id
  - Supports both base model and fine-tuned model sampling
  - Optional logprob computation
- **Description**: Generates samples from the model using specified sampling parameters

---

## 6. FUTURES RESOURCE (AsyncFuturesResource)

**Module**: `/tinker/resources/futures.py`

### 6.1 retrieve
- **HTTP Method**: POST
- **Path**: `/api/v1/retrieve_future`
- **Request Type**: `FutureRetrieveRequest`
- **Request Fields**:
  - `request_id: RequestID` (required)
- **Response Type**: `FutureRetrieveResponse` (Union type)
- **Response Union Types**:
  - `TryAgainResponse` (operation still pending)
  - `ForwardBackwardOutput`
  - `OptimStepResponse`
  - `SaveWeightsResponse`
  - `LoadWeightsResponse`
  - `SaveWeightsForSamplerResponse`
  - `CreateModelResponse`
  - `UnloadModelResponse`
  - `RequestFailedResponse`
- **Idempotency**: Yes
- **Description**: Retrieves the result of a future by its request ID (polling mechanism)

---

## 7. TELEMETRY RESOURCE (AsyncTelemetryResource)

**Module**: `/tinker/resources/telemetry.py`

**Special Features**: Has `with_raw_response` property for accessing raw response objects

### 7.1 send
- **HTTP Method**: POST
- **Path**: `/api/v1/telemetry`
- **Request Type**: `TelemetrySendRequest`
- **Request Fields**:
  - `events: List[TelemetryEvent]` (required)
  - `platform: str` (required)
  - `sdk_version: str` (required)
  - `session_id: str` (required)
- **Response Type**: `TelemetryResponse`
- **Idempotency**: Yes
- **Special**: Raw response wrapper available via `with_raw_response`
- **Description**: Accepts batches of SDK telemetry events for analytics

---

## Cross-Cutting Patterns

### Idempotency Pattern
**Endpoints supporting idempotency_key parameter:**
- Models: create, get_info, unload
- Weights: load, save, save_for_sampler
- Training: forward, forward_backward, optim_step
- Sampling: asample
- Futures: retrieve
- Telemetry: send
- Service: create_session

### Async/Future Pattern
**Long-running operations return `UntypedAPIFuture`:**
- Models: create, unload
- Weights: load, save, save_for_sampler
- Training: forward, forward_backward, optim_step
- Sampling: asample

**Polling via Futures Resource:**
- Call long-running endpoint -> get request_id
- Poll futures.retrieve(request_id) -> get result or TryAgainResponse

### Request Envelope Pattern
**All POST request bodies include a `type` field:**
- `CreateModelRequest`: type="create_model"
- `GetInfoRequest`: type="get_info"
- `LoadWeightsRequest`: type="load_weights"
- `SaveWeightsRequest`: type="save_weights"
- `SaveWeightsForSamplerRequest`: type="save_weights_for_sampler"
- `OptimStepRequest`: type="optim_step"
- `SampleRequest`: type="sample"
- `CreateSessionRequest`: type="create_session"
- `CreateSamplingSessionRequest`: type="create_sampling_session"

### Sequence ID Pattern
**Deterministic request ID generation:**
- Training: ForwardRequest.seq_id, ForwardBackwardRequest.seq_id, OptimStepRequest.seq_id
- Sampling: SampleRequest.seq_id
- Load/Save: seq_id parameter

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total Endpoints** | 20 |
| **HTTP GET** | 4 |
| **HTTP POST** | 15 |
| **HTTP DELETE** | 1 |
| **Idempotent Endpoints** | 12 |
| **Async/Future Endpoints** | 9 |
| **Streaming** | 0 |

**Resource Distribution (7 resources):**
- Service: 5 endpoints (2 GET, 3 POST)
- Models: 3 endpoints (3 POST)
- Weights: 6 endpoints (2 GET, 3 POST, 1 DELETE)
- Training: 3 endpoints (3 POST)
- Sampling: 1 endpoint (1 POST)
- Futures: 1 endpoint (1 POST)
- Telemetry: 1 endpoint (1 POST)

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinker Python SDK resource modules*
