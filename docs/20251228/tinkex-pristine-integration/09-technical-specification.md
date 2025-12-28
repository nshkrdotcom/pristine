# Technical Specification: Pristine Enhancements for Tinkex v2

## 1. Introduction

### 1.1 Purpose

This specification defines the technical requirements and implementation details for enhancing Pristine to support generation of a production-quality Tinkex v2 client. The goal is to minimize hand-written code in Tinkex by maximizing Pristine's generation capabilities.

### 1.2 Scope

This specification covers:
- Type system integration (Sinter already supports discriminated unions and literals)
- Manifest schema extensions for code generation
- Code generation improvements
- Runtime pipeline enhancements

> **Note**: Sinter already provides discriminated union support via
> `{:discriminated_union, opts}` type (see `sinter/lib/sinter/types.ex:320-368`).
> The enhancements in this spec focus on integrating these existing capabilities
> into Pristine's code generation pipeline.

### 1.3 References

| Document | Location |
|----------|----------|
| Critical Self-Assessment | `00-critical-self-assessment.md` |
| Client Architecture Analysis | `01-client-architecture-analysis.md` |
| Streaming/Futures Analysis | `02-streaming-futures-analysis.md` |
| Types/Models Analysis | `03-types-models-analysis.md` |
| Resources/Endpoints Analysis | `04-resources-endpoints-analysis.md` |
| Prior Work Analysis | `05-prior-work-analysis.md` |
| Utilities Analysis | `06-utilities-helpers-analysis.md` |
| Gap Analysis | `07-gap-analysis.md` |
| Enhancement Roadmap | `08-enhancement-roadmap.md` |

---

## 2. Type System Specification

### 2.1 Discriminated Union Types

#### 2.1.1 Manifest Schema

```json
{
  "types": {
    "ModelInputChunk": {
      "kind": "union",
      "discriminator": {
        "field": "type",
        "mapping": {
          "encoded_text": "EncodedTextChunk",
          "image": "ImageChunk",
          "image_asset_pointer": "ImageAssetPointerChunk"
        }
      },
      "description": "A chunk of model input"
    }
  }
}
```

#### 2.1.2 Elixir Struct Definition

```elixir
defmodule Pristine.Manifest.UnionType do
  @moduledoc "Represents a discriminated union type"

  defstruct [
    :name,
    :description,
    :discriminator_field,
    :variants  # map of discriminator_value => type_ref
  ]

  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t() | nil,
    discriminator_field: String.t(),
    variants: %{String.t() => String.t()}
  }
end
```

#### 2.1.3 Generated Code Pattern

```elixir
defmodule Tinkex.Types.ModelInputChunk do
  @moduledoc "A chunk of model input"

  alias Tinkex.Types.{EncodedTextChunk, ImageChunk, ImageAssetPointerChunk}

  @type t :: EncodedTextChunk.t() | ImageChunk.t() | ImageAssetPointerChunk.t()

  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(%{"type" => "encoded_text"} = data), do: EncodedTextChunk.decode(data)
  def decode(%{"type" => "image"} = data), do: ImageChunk.decode(data)
  def decode(%{"type" => "image_asset_pointer"} = data), do: ImageAssetPointerChunk.decode(data)
  def decode(%{"type" => type}), do: {:error, {:unknown_variant, type}}
  def decode(_), do: {:error, :missing_discriminator}

  @spec encode(t()) :: map()
  def encode(%EncodedTextChunk{} = v), do: EncodedTextChunk.encode(v)
  def encode(%ImageChunk{} = v), do: ImageChunk.encode(v)
  def encode(%ImageAssetPointerChunk{} = v), do: ImageAssetPointerChunk.encode(v)
end
```

### 2.2 Literal Types

#### 2.2.1 Manifest Schema

```json
{
  "fields": {
    "type": {
      "type": "literal",
      "value": "encoded_text",
      "description": "Type discriminator"
    }
  }
}
```

#### 2.2.2 Field Struct Extension

```elixir
defmodule Pristine.Manifest.Field do
  defstruct [
    :name,
    :type,
    :literal_value,  # NEW: for literal types
    :required,
    :default,
    :description,
    :type_ref,       # NEW: for type references
    :validator,      # NEW: custom validation
    :serializer      # NEW: custom serialization
  ]
end
```

#### 2.2.3 Generated Sinter Schema

```elixir
def schema do
  Sinter.Schema.define([
    {:type, {:literal, "encoded_text"}, [required: true]}
  ])
end
```

### 2.3 Nested Type References

#### 2.3.1 Manifest Schema

```json
{
  "types": {
    "SampleResponse": {
      "fields": {
        "sequences": {
          "type": "array",
          "items": {"$ref": "SampledSequence"},
          "required": true
        }
      }
    }
  }
}
```

#### 2.3.2 Resolution Algorithm

```elixir
defmodule Pristine.TypeResolver do
  def resolve_type(type_def, all_types) do
    case type_def do
      %{"$ref" => ref_name} ->
        {:ref, ref_name, Map.get(all_types, ref_name)}

      %{"type" => "array", "items" => items} ->
        {:array, resolve_type(items, all_types)}

      %{"type" => primitive} ->
        {:primitive, primitive}
    end
  end
end
```

#### 2.3.3 Generated Code

```elixir
defmodule Tinkex.Types.SampleResponse do
  alias Tinkex.Types.SampledSequence

  defstruct [:sequences, :type, :prompt_logprobs]

  def schema do
    Sinter.Schema.define([
      {:sequences, {:array, {:object, SampledSequence.schema()}}, [required: true]},
      {:type, {:literal, "sample"}, [default: "sample"]},
      {:prompt_logprobs, {:array, :float}, []}
    ])
  end

  def decode(data) do
    # Note: Sinter.Validator.validate/2 is the correct API
    # Output keys match input keys (string -> string, atom -> atom)
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok, struct(__MODULE__, atomize_keys(validated))}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end
end
```

---

## 3. Manifest Schema Specification

### 3.1 Root Manifest Structure

```json
{
  "name": "Tinkex",
  "version": "2.0.0",
  "base_url": "https://api.tinker.ai/v1",

  "auth": {
    "type": "api_key",
    "header": "X-API-Key",
    "env_var": "TINKER_API_KEY",
    "prefix": null
  },

  "defaults": {
    "timeout": 60000,
    "max_retries": 10,
    "retry_delay": 500,
    "max_retry_delay": 10000
  },

  "error_types": {
    "400": {"name": "BadRequestError", "retryable": false},
    "401": {"name": "AuthenticationError", "retryable": false},
    "403": {"name": "PermissionDeniedError", "retryable": false},
    "404": {"name": "NotFoundError", "retryable": false},
    "408": {"name": "RequestTimeoutError", "retryable": true},
    "409": {"name": "ConflictError", "retryable": true},
    "429": {"name": "RateLimitError", "retryable": true},
    "5xx": {"name": "ServerError", "retryable": true}
  },

  "endpoints": [...],
  "types": {...}
}
```

### 3.2 Endpoint Schema Extension

```json
{
  "endpoints": {
    "create_model": {
      "id": "create_model",
      "method": "POST",
      "path": "/api/v1/create_model",
      "resource": "models",
      "description": "Creates a new model",

      "request": {"$ref": "CreateModelRequest"},
      "response": {"$ref": "UntypedAPIFuture"},

      "async": true,
      "poll_endpoint": "retrieve_future",
      "timeout": 300000,

      "streaming": false,
      "stream_format": null,
      "event_types": null,

      "idempotency": true,
      "idempotency_header": "X-Idempotency-Key",

      "retry": {
        "max_retries": 10,
        "retry_on": [408, 429, 500, 502, 503, 504]
      },

      "deprecated": false,
      "tags": ["models", "training"]
    },

    "create_sample_stream": {
      "id": "create_sample_stream",
      "method": "POST",
      "path": "/api/v1/sample",
      "resource": "sampling",

      "streaming": true,
      "stream_format": "sse",
      "event_types": [
        "message_start",
        "content_block_start",
        "content_block_delta",
        "content_block_stop",
        "message_stop"
      ],

      "request": {"$ref": "SampleRequest"},
      "response": {"$ref": "SampleStreamEvent"}
    }
  }
}
```

### 3.3 Elixir Manifest Structs

```elixir
defmodule Pristine.Manifest do
  defstruct [
    :name,
    :version,
    :base_url,
    :auth,
    :defaults,
    :error_types,
    :endpoints,
    :types
  ]
end

defmodule Pristine.Manifest.Auth do
  defstruct [
    :type,        # "api_key" | "bearer" | "basic"
    :header,      # Header name
    :env_var,     # Environment variable name
    :prefix       # Optional prefix (e.g., "Bearer ")
  ]
end

defmodule Pristine.Manifest.Endpoint do
  defstruct [
    # Existing fields
    :id,
    :method,
    :path,
    :description,
    :resource,
    :request,
    :response,
    :retry,
    :telemetry,
    :streaming,
    :headers,
    :query,
    :body_type,
    :content_type,
    :auth,
    :circuit_breaker,
    :rate_limit,
    :idempotency,

    # New fields
    :async,
    :poll_endpoint,
    :timeout,
    :stream_format,
    :event_types,
    :idempotency_header,
    :deprecated,
    :tags,
    :response_unwrap
  ]
end
```

---

## 4. Code Generation Specification

### 4.1 Resource Module Generation

#### 4.1.1 Function Signature Pattern

**Input Manifest**:
```json
{
  "id": "create",
  "async": true,
  "request": {"$ref": "CreateModelRequest"}
}
```

**CreateModelRequest Type**:
```json
{
  "fields": {
    "session_id": {"type": "string", "required": true},
    "model_seq_id": {"type": "integer", "required": true},
    "base_model": {"type": "string", "required": true},
    "user_metadata": {"type": "object", "required": false},
    "lora_config": {"$ref": "LoraConfig", "required": false}
  }
}
```

**Generated Elixir**:
```elixir
defmodule Tinkex.Resources.Models do
  @moduledoc "Model management operations"

  alias Tinkex.Types.{CreateModelRequest, LoraConfig}
  alias Pristine.Runtime.Future

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc """
  Creates a new model with optional LoRA fine-tuning configuration.

  ## Parameters

    * `session_id` - The session ID (required)
    * `model_seq_id` - Model sequence ID (required)
    * `base_model` - Base model name, e.g., "Qwen/Qwen3-8B" (required)
    * `opts` - Optional parameters:
      * `:user_metadata` - Custom metadata dictionary
      * `:lora_config` - LoRA configuration struct
      * `:idempotency_key` - Idempotency key for request deduplication
      * `:timeout` - Request timeout in milliseconds

  ## Returns

    * `{:ok, %Future{}}` - Future that resolves to CreateModelResponse
    * `{:error, %Error{}}` - Error with details

  ## Example

      {:ok, future} = Tinkex.Resources.Models.create(
        client.models,
        "session-123",
        1,
        "Qwen/Qwen3-8B",
        lora_config: %LoraConfig{rank: 8}
      )
      {:ok, result} = Future.await(future)

  """
  @spec create(t(), String.t(), integer(), String.t(), keyword()) ::
          {:ok, Future.t()} | {:error, Pristine.Error.t()}
  def create(%__MODULE__{context: context}, session_id, model_seq_id, base_model, opts \\ []) do
    payload = %{
      "session_id" => session_id,
      "model_seq_id" => model_seq_id,
      "base_model" => base_model,
      "type" => "create_model"
    }
    |> maybe_put("user_metadata", Keyword.get(opts, :user_metadata))
    |> maybe_put("lora_config", encode_lora_config(Keyword.get(opts, :lora_config)))

    Pristine.Runtime.execute_future(context, "create_model", payload, opts)
  end
end
```

#### 4.1.2 Function Variants

For endpoints with different modes, generate separate functions:

```elixir
# Standard sync request
@spec create_sample(t(), map(), keyword()) :: {:ok, SampleResponse.t()} | {:error, Error.t()}
def create_sample(resource, payload, opts \\ [])

# Streaming variant
@spec create_sample_stream(t(), map(), keyword()) :: {:ok, StreamResponse.t()} | {:error, Error.t()}
def create_sample_stream(resource, payload, opts \\ [])

# Async variant (returns future)
@spec create_sample_async(t(), map(), keyword()) :: {:ok, Future.t()} | {:error, Error.t()}
def create_sample_async(resource, payload, opts \\ [])
```

### 4.2 Type Module Generation

#### 4.2.1 Standard Type Pattern

```elixir
defmodule Tinkex.Types.SampledSequence do
  @moduledoc "A sampled sequence from the model"

  @enforce_keys [:stop_reason, :tokens]
  defstruct [
    :stop_reason,
    :tokens,
    :logprobs
  ]

  @type stop_reason :: :length | :stop
  @type t :: %__MODULE__{
    stop_reason: stop_reason(),
    tokens: [integer()],
    logprobs: [float()] | nil
  }

  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:stop_reason, {:choices, ["length", "stop"]}, [required: true]},
      {:tokens, {:array, :integer}, [required: true]},
      {:logprobs, {:array, :float}, []}
    ])
  end

  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    # Sinter.Validator.validate/2 - note schema comes first
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      # Handle both string and atom keys from validation output
      stop_reason = validated["stop_reason"] || validated[:stop_reason]
      tokens = validated["tokens"] || validated[:tokens]
      logprobs = validated["logprobs"] || validated[:logprobs]

      {:ok, %__MODULE__{
        stop_reason: String.to_existing_atom(stop_reason),
        tokens: tokens,
        logprobs: logprobs
      }}
    end
  end

  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "stop_reason" => to_string(struct.stop_reason),
      "tokens" => struct.tokens,
      "logprobs" => struct.logprobs
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
```

### 4.3 Client Module Generation

```elixir
defmodule Tinkex.Client do
  @moduledoc """
  Tinkex API Client

  ## Configuration

  The client can be configured via environment variables:

    * `TINKER_API_KEY` - API key for authentication (required)
    * `TINKER_BASE_URL` - Base URL override (optional)

  ## Example

      # Initialize with environment variable
      {:ok, client} = Tinkex.Client.new()

      # Or with explicit API key
      {:ok, client} = Tinkex.Client.new(api_key: "tml-...")

      # Access resources
      {:ok, models} = Tinkex.Resources.Models.list(client.models)

  """

  alias Tinkex.Resources.{Service, Models, Weights, Training, Sampling, Futures, Telemetry}

  defstruct [
    :context,
    :service,
    :models,
    :weights,
    :training,
    :sampling,
    :futures,
    :telemetry
  ]

  @type t :: %__MODULE__{
    context: Pristine.Core.Context.t(),
    service: Service.t(),
    models: Models.t(),
    weights: Weights.t(),
    training: Training.t(),
    sampling: Sampling.t(),
    futures: Futures.t(),
    telemetry: Telemetry.t()
  }

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("TINKER_API_KEY")
    base_url = Keyword.get(opts, :base_url) || System.get_env("TINKER_BASE_URL") ||
               "https://api.tinker.ai/v1"

    unless api_key do
      {:error, :missing_api_key}
    else
      context = Pristine.Core.Context.new(
        base_url: base_url,
        transport: Pristine.Adapters.Transport.Finch,
        serializer: Pristine.Adapters.Serializer.JSON,
        auth: [Pristine.Adapters.Auth.APIKey.new(api_key, header: "X-API-Key")]
      )

      {:ok, %__MODULE__{
        context: context,
        service: %Service{context: context},
        models: %Models{context: context},
        weights: %Weights{context: context},
        training: %Training{context: context},
        sampling: %Sampling{context: context},
        futures: %Futures{context: context},
        telemetry: %Telemetry{context: context}
      }}
    end
  end
end
```

---

## 5. Runtime Pipeline Specification

> **NOTE**: Several features described in this section already exist in Pristine:
> - Status code mapping: `lib/pristine/error.ex` (lines 196-204)
> - Idempotency key generation: `lib/pristine/core/pipeline.ex` (lines 326-332)
> - Error types: `lib/pristine/error.ex` (unified struct with `:type` field)
>
> The enhancements below describe optional typed exception modules for more
> granular pattern matching, not a replacement for existing functionality.

### 5.1 Error Hierarchy (OPTIONAL ENHANCEMENT)

The existing `Pristine.Error` struct with status-to-type mapping is production-ready.
The typed exception modules below are an optional enhancement for applications
that prefer pattern matching on exception types:

```elixir
defmodule Pristine.Errors do
  @moduledoc """
  OPTIONAL typed error hierarchy for API responses.

  Note: `Pristine.Error` already provides status code mapping via `status_to_type/1`.
  These typed exceptions are an optional enhancement for applications preferring
  exception-based pattern matching.
  """

  defmodule APIError do
    @moduledoc "Base API error"
    defexception [:message, :request, :body]

    @type t :: %__MODULE__{
      message: String.t(),
      request: map() | nil,
      body: map() | binary() | nil
    }
  end

  defmodule BadRequestError do
    @moduledoc "400 Bad Request"
    defexception [:message, :request, :body, status_code: 400]
  end

  defmodule AuthenticationError do
    @moduledoc "401 Unauthorized"
    defexception [:message, :request, :body, status_code: 401]
  end

  defmodule PermissionDeniedError do
    @moduledoc "403 Forbidden"
    defexception [:message, :request, :body, status_code: 403]
  end

  defmodule NotFoundError do
    @moduledoc "404 Not Found"
    defexception [:message, :request, :body, status_code: 404]
  end

  defmodule ConflictError do
    @moduledoc "409 Conflict"
    defexception [:message, :request, :body, status_code: 409]
  end

  defmodule RateLimitError do
    @moduledoc "429 Too Many Requests"
    defexception [:message, :request, :body, :retry_after, status_code: 429]
  end

  defmodule ServerError do
    @moduledoc "5xx Server Error"
    defexception [:message, :request, :body, :status_code]
  end

  @spec from_response(integer(), map(), map()) :: Exception.t()
  def from_response(400, body, request), do: %BadRequestError{message: extract_message(body), body: body, request: request}
  def from_response(401, body, request), do: %AuthenticationError{message: extract_message(body), body: body, request: request}
  def from_response(403, body, request), do: %PermissionDeniedError{message: extract_message(body), body: body, request: request}
  def from_response(404, body, request), do: %NotFoundError{message: extract_message(body), body: body, request: request}
  def from_response(409, body, request), do: %ConflictError{message: extract_message(body), body: body, request: request}
  def from_response(429, body, request) do
    %RateLimitError{
      message: extract_message(body),
      body: body,
      request: request,
      retry_after: extract_retry_after(body)
    }
  end
  def from_response(status, body, request) when status >= 500 do
    %ServerError{message: extract_message(body), body: body, request: request, status_code: status}
  end

  defp extract_message(%{"message" => msg}), do: msg
  defp extract_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_message(_), do: "Unknown error"

  defp extract_retry_after(%{"retry_after" => seconds}), do: seconds
  defp extract_retry_after(_), do: nil
end
```

### 5.2 Future Implementation

```elixir
defmodule Pristine.Runtime.Future do
  @moduledoc """
  Represents an async operation that can be polled for results.

  ## Usage

      {:ok, future} = SomeResource.async_operation(client.resource, params)

      # Await with default timeout
      {:ok, result} = Future.await(future)

      # Await with custom timeout
      {:ok, result} = Future.await(future, timeout: 60_000)

      # Check without blocking
      case Future.poll(future) do
        {:ok, result} -> # Completed
        {:pending, status} -> # Still processing
        {:error, reason} -> # Failed
      end

  """

  defstruct [
    :request_id,
    :context,
    :poll_endpoint,
    :response_type,
    :cached_result,
    :start_time
  ]

  @type t :: %__MODULE__{
    request_id: String.t(),
    context: Pristine.Core.Context.t(),
    poll_endpoint: String.t(),
    response_type: module(),
    cached_result: term() | nil,
    start_time: integer()
  }

  @spec await(t(), keyword()) :: {:ok, term()} | {:error, term()}
  def await(%__MODULE__{cached_result: result} = _future, _opts) when not is_nil(result) do
    {:ok, result}
  end

  def await(%__MODULE__{} = future, opts) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    poll_interval = Keyword.get(opts, :poll_interval, 1000)
    max_poll_interval = Keyword.get(opts, :max_poll_interval, 30_000)

    deadline = if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    do_poll(future, poll_interval, max_poll_interval, deadline, 0)
  end

  defp do_poll(future, interval, max_interval, deadline, iteration) do
    if deadline != :infinity and System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case poll(future) do
        {:ok, result} ->
          {:ok, result}

        {:pending, _status} ->
          :timer.sleep(interval)
          next_interval = min(interval * 2, max_interval)
          do_poll(future, next_interval, max_interval, deadline, iteration + 1)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec poll(t()) :: {:ok, term()} | {:pending, map()} | {:error, term()}
  def poll(%__MODULE__{} = future) do
    payload = %{"request_id" => future.request_id}

    case Pristine.Core.Pipeline.execute(future.context, future.poll_endpoint, payload) do
      {:ok, %{"type" => "try_again"} = response} ->
        {:pending, response}

      {:ok, %{"type" => "request_failed"} = response} ->
        {:error, {:request_failed, response}}

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec combine([t()], (list() -> term())) :: t()
  def combine(futures, transform_fn) when is_list(futures) do
    %__MODULE__{
      request_id: "combined-#{:erlang.unique_integer([:positive])}",
      context: hd(futures).context,
      poll_endpoint: nil,
      response_type: nil,
      cached_result: nil,
      start_time: System.monotonic_time(:millisecond),
      # Store futures and transform for combined polling
      __combined__: {futures, transform_fn}
    }
  end
end
```

### 5.3 Enhanced Streaming

```elixir
defmodule Pristine.Runtime.StreamResponse do
  @moduledoc """
  Handles SSE streaming with event type dispatch.
  """

  defstruct [
    :response,
    :decoder,
    :event_handler,
    :last_event_id
  ]

  @type event_handler :: (ServerSentEvent.t() -> :ok | {:error, term()})

  @spec new(Finch.Response.t(), keyword()) :: t()
  def new(response, opts \\ []) do
    %__MODULE__{
      response: response,
      decoder: Pristine.Adapters.SSEDecoder.new(),
      event_handler: Keyword.get(opts, :event_handler),
      last_event_id: nil
    }
  end

  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{} = stream) do
    Stream.resource(
      fn -> stream end,
      &next_event/1,
      &cleanup/1
    )
  end

  defp next_event(%__MODULE__{decoder: decoder, response: response} = stream) do
    case Pristine.Adapters.SSEDecoder.next(decoder, response) do
      {:event, event, new_decoder} ->
        new_stream = %{stream |
          decoder: new_decoder,
          last_event_id: event.id || stream.last_event_id
        }
        {[event], new_stream}

      :done ->
        {:halt, stream}

      {:error, reason} ->
        throw({:stream_error, reason})
    end
  end

  defp cleanup(%__MODULE__{response: response}) do
    # Ensure connection is closed
    :ok
  end

  @spec dispatch_event(ServerSentEvent.t(), module()) :: {:ok, term()} | {:error, term()}
  def dispatch_event(%{event: event_type, data: data}, handler_module) do
    case event_type do
      "message_start" -> handler_module.on_message_start(Jason.decode!(data))
      "content_block_start" -> handler_module.on_content_block_start(Jason.decode!(data))
      "content_block_delta" -> handler_module.on_content_block_delta(Jason.decode!(data))
      "content_block_stop" -> handler_module.on_content_block_stop(Jason.decode!(data))
      "message_stop" -> handler_module.on_message_stop(Jason.decode!(data))
      "error" -> handler_module.on_error(Jason.decode!(data))
      _ -> handler_module.on_unknown(event_type, data)
    end
  end
end
```

---

## 6. Implementation Checklist

### 6.1 Type System
- [ ] Add `kind` field to type definition (union, object, enum)
- [ ] Add `discriminator` support for unions
- [ ] Implement type reference resolution
- [ ] Add literal type validation
- [ ] Generate union decode/encode functions

### 6.2 Manifest Schema
- [ ] Add `base_url` and `auth` to root manifest
- [ ] Add `async`, `poll_endpoint`, `timeout` to endpoints
- [ ] Add `stream_format`, `event_types` to endpoints
- [ ] Add `error_types` mapping
- [ ] Add `response_unwrap` path

### 6.3 Code Generation
- [ ] Extract typed parameters from request types
- [ ] Generate typed function signatures
- [ ] Generate streaming variants
- [ ] Generate async variants
- [ ] Generate comprehensive @doc

### 6.4 Runtime
- [x] Status code to error type mapping (EXISTS: lib/pristine/error.ex:196-204)
- [x] Idempotency key generation (EXISTS: lib/pristine/core/pipeline.ex:326-332)
- [ ] Implement typed error hierarchy (OPTIONAL: for exception-based matching)
- [ ] Add Retry-After header parsing
- [ ] Implement Future with polling
- [ ] Enhance StreamResponse with dispatch

### 6.5 Utilities
- [ ] Implement query string format options
- [ ] Add platform telemetry headers
- [ ] Integrate with multipart_ex

---

## 7. Testing Requirements

### 7.1 Unit Tests
- Type parsing and generation for each type kind
- Manifest parsing with new fields
- Code generation output verification
- Error mapping correctness

### 7.2 Integration Tests
- Full manifest to client generation
- Mock server request/response cycles
- Streaming event handling
- Future polling lifecycle

### 7.3 Live API Tests
- Optional tests against real Tinker API
- Gated by environment variable

---

*Document created: 2025-12-28*
*Version: 1.0*
*Status: Draft*
