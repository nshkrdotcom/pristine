defmodule Tinkex.TrainingClient do
  @moduledoc """
  High-level training client for model fine-tuning.

  A struct-based client that wraps training API operations with convenient
  async patterns and typed responses. For production use with full state
  management, consider using the GenServer-based implementation.

  ## Usage

      config = Tinkex.Config.new(api_key: "tml-key")
      client = Tinkex.TrainingClient.new("model-123", "session-abc", config)

      # Forward-backward pass
      data = [Tinkex.Types.Datum.new(model_input: ModelInput.from_ints([1, 2, 3]))]
      input = %Tinkex.Types.ForwardBackwardInput{
        data: data,
        loss_fn: :cross_entropy,
        loss_fn_config: %{}
      }
      {:ok, task} = Tinkex.TrainingClient.forward_backward(client, input)
      {:ok, output} = Task.await(task)

      # Optimizer step
      adam = %Tinkex.Types.AdamParams{learning_rate: 0.001}
      {:ok, task} = Tinkex.TrainingClient.optim_step(client, adam)

      # Save checkpoint
      {:ok, response} = Tinkex.TrainingClient.save_state(client, "checkpoint-1")

  ## Training Loop Pattern

      for epoch <- 1..num_epochs do
        for batch <- batches do
          {:ok, task} = TrainingClient.forward_backward(client, batch, :cross_entropy)
          {:ok, output} = Task.await(task)
          IO.puts("Loss: \#{output.metrics["loss"]}")

          {:ok, task} = TrainingClient.optim_step(client, adam_params)
          Task.await(task)
        end

        # Save checkpoint each epoch
        TrainingClient.save_state(client, "epoch-\#{epoch}")
      end
  """

  alias Tinkex.API.Training, as: TrainingAPI
  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.Future

  alias Tinkex.Types.{
    AdamParams,
    Datum,
    ForwardBackwardInput,
    ForwardBackwardOutput,
    GetInfoRequest,
    GetInfoResponse,
    LoadWeightsRequest,
    LoadWeightsResponse,
    SaveWeightsForSamplerRequest,
    SaveWeightsRequest,
    SaveWeightsResponse,
    UnloadModelRequest,
    UnloadModelResponse
  }

  @enforce_keys [:model_id, :session_id, :config]
  defstruct [
    :model_id,
    :session_id,
    :config,
    :training_api,
    :weights_api,
    :futures_api,
    :models_api,
    :seq_counter
  ]

  @type t :: %__MODULE__{
          model_id: String.t(),
          session_id: String.t(),
          config: Config.t(),
          training_api: module() | nil,
          weights_api: module() | nil,
          futures_api: module() | nil,
          models_api: module() | nil,
          seq_counter: reference() | nil
        }

  @doc """
  Create a new TrainingClient.

  ## Options

    * `:training_api` - Module implementing training API (default: `Tinkex.API.Training`)
    * `:weights_api` - Module implementing weights API (default: `Tinkex.API.Weights`)
    * `:futures_api` - Module implementing futures polling (default: `Tinkex.Future`)
    * `:models_api` - Module implementing models API (default: `Tinkex.API.Models`)
  """
  @spec new(String.t(), String.t(), Config.t(), keyword()) :: t()
  def new(model_id, session_id, config, opts \\ []) do
    %__MODULE__{
      model_id: model_id,
      session_id: session_id,
      config: config,
      training_api: Keyword.get(opts, :training_api),
      weights_api: Keyword.get(opts, :weights_api),
      futures_api: Keyword.get(opts, :futures_api),
      models_api: Keyword.get(opts, :models_api),
      seq_counter: :atomics.new(1, [])
    }
  end

  @doc """
  Perform a forward-backward pass.

  ## Parameters

    * `client` - TrainingClient instance
    * `input` - ForwardBackwardInput struct or data list
    * `loss_fn` - Loss function (when input is data list)
    * `opts` - Options

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to ForwardBackwardOutput
    * `{:error, Error.t()}` - Error if request fails
  """
  @spec forward_backward(t(), ForwardBackwardInput.t() | [Datum.t()], atom() | nil, keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward_backward(client, input, loss_fn \\ nil, opts \\ [])

  def forward_backward(%__MODULE__{} = client, %ForwardBackwardInput{} = input, _loss_fn, opts) do
    seq_id = next_seq_id(client)

    request = %{
      model_id: client.model_id,
      seq_id: seq_id,
      forward_backward_input: encode_forward_backward_input(input)
    }

    api = training_api(client)

    case api.forward_backward_future(client.config, request) do
      {:ok, %{"request_id" => request_id}} ->
        futures = futures_api(client)
        task = futures.poll(client.config, request_id, opts)
        {:ok, task}

      {:ok, response} ->
        {:error,
         Error.new(:validation, "Unexpected forward_backward response: #{inspect(response)}")}

      {:error, error} ->
        {:error, error}
    end
  end

  def forward_backward(%__MODULE__{} = client, data, loss_fn, opts) when is_list(data) do
    input = %ForwardBackwardInput{
      data: data,
      loss_fn: loss_fn || :cross_entropy,
      loss_fn_config: Keyword.get(opts, :loss_fn_config, %{})
    }

    forward_backward(client, input, nil, opts)
  end

  @doc """
  Perform a forward-only pass (for custom loss computation).

  ## Parameters

    * `client` - TrainingClient instance
    * `data` - List of Datum structs
    * `opts` - Options

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to forward output with logprobs
    * `{:error, Error.t()}` - Error if request fails
  """
  @spec forward(t(), [Datum.t()], keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def forward(%__MODULE__{} = client, data, opts \\ []) when is_list(data) do
    seq_id = next_seq_id(client)

    request = %{
      model_id: client.model_id,
      seq_id: seq_id,
      forward_input: encode_data(data)
    }

    api = training_api(client)

    case api.forward_future(client.config, request) do
      {:ok, %{"request_id" => request_id}} ->
        futures = futures_api(client)
        task = futures.poll(client.config, request_id, opts)
        {:ok, task}

      {:ok, response} ->
        {:error, Error.new(:validation, "Unexpected forward response: #{inspect(response)}")}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Perform an optimizer step.

  ## Parameters

    * `client` - TrainingClient instance
    * `adam_params` - AdamParams struct
    * `opts` - Options

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to OptimStepResponse
    * `{:error, Error.t()}` - Error if request fails
  """
  @spec optim_step(t(), AdamParams.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def optim_step(%__MODULE__{} = client, %AdamParams{} = adam_params, opts \\ []) do
    seq_id = next_seq_id(client)

    request = %{
      model_id: client.model_id,
      seq_id: seq_id,
      adam_params: adam_params
    }

    api = training_api(client)

    case api.optim_step_future(client.config, request) do
      {:ok, %{"request_id" => request_id}} ->
        futures = futures_api(client)
        task = futures.poll(client.config, request_id, opts)
        {:ok, task}

      {:ok, response} ->
        {:error, Error.new(:validation, "Unexpected optim_step response: #{inspect(response)}")}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Save model state (weights and optionally optimizer state).

  ## Parameters

    * `client` - TrainingClient instance
    * `name` - Checkpoint name
    * `opts` - Options:
      * `:include_optimizer` - Include optimizer state (default: false)

  ## Returns

    * `{:ok, SaveWeightsResponse.t()}` - Response with checkpoint path
    * `{:error, Error.t()}` - Error if save fails
  """
  @spec save_state(t(), String.t(), keyword()) ::
          {:ok, SaveWeightsResponse.t()} | {:error, Error.t()}
  def save_state(%__MODULE__{} = client, name, opts \\ []) do
    seq_id = next_seq_id(client)
    include_optimizer = Keyword.get(opts, :include_optimizer, false)
    checkpoint_type = if include_optimizer, do: "full", else: "weights"

    request = %SaveWeightsRequest{
      model_id: client.model_id,
      seq_id: seq_id,
      path: name,
      type: checkpoint_type
    }

    api = weights_api(client)

    case api.save_weights(client.config, request) do
      {:ok, response} ->
        {:ok, SaveWeightsResponse.from_json(response)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Load model state from a checkpoint.

  ## Parameters

    * `client` - TrainingClient instance
    * `path` - Tinker path to checkpoint
    * `opts` - Options:
      * `:include_optimizer` - Load optimizer state (default: false)

  ## Returns

    * `{:ok, LoadWeightsResponse.t()}` - Response with loaded path
    * `{:error, Error.t()}` - Error if load fails
  """
  @spec load_state(t(), String.t(), keyword()) ::
          {:ok, LoadWeightsResponse.t()} | {:error, Error.t()}
  def load_state(%__MODULE__{} = client, path, opts \\ []) do
    seq_id = next_seq_id(client)
    include_optimizer = Keyword.get(opts, :include_optimizer, false)

    request =
      LoadWeightsRequest.new(client.model_id, path,
        seq_id: seq_id,
        optimizer: include_optimizer
      )

    api = weights_api(client)

    case api.load_weights(client.config, request) do
      {:ok, response} ->
        {:ok, LoadWeightsResponse.from_json(response)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Save weights for use with a sampling client.

  ## Parameters

    * `client` - TrainingClient instance
    * `name` - Checkpoint name
    * `opts` - Options

  ## Returns

    * `{:ok, map()}` - Response with sampling_session_id
    * `{:error, Error.t()}` - Error if save fails
  """
  @spec save_weights_for_sampler(t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def save_weights_for_sampler(%__MODULE__{} = client, name, opts \\ []) do
    seq_id = next_seq_id(client)
    sampling_seq_id = Keyword.get(opts, :sampling_session_seq_id, 0)

    request = %SaveWeightsForSamplerRequest{
      model_id: client.model_id,
      seq_id: seq_id,
      path: name,
      sampling_session_seq_id: sampling_seq_id,
      type: "sampler"
    }

    api = weights_api(client)
    api.save_weights_for_sampler(client.config, request)
  end

  @doc """
  Get the next sequence ID for this client.

  Uses atomic increment for thread-safe sequence generation.
  """
  @spec next_seq_id(t()) :: integer()
  def next_seq_id(%__MODULE__{seq_counter: counter}) do
    :atomics.add_get(counter, 1, 1)
  end

  @doc """
  Parse a raw forward-backward response into typed structure.

  ## Parameters

    * `response` - Raw response map from API

  ## Returns

    * `{:ok, ForwardBackwardOutput.t()}` - Parsed output
    * `{:error, Error.t()}` - Parse error
  """
  @spec parse_forward_backward_response(map()) ::
          {:ok, ForwardBackwardOutput.t()} | {:error, Error.t()}
  def parse_forward_backward_response(response) when is_map(response) do
    {:ok, ForwardBackwardOutput.from_json(response)}
  rescue
    e ->
      {:error, Error.new(:validation, "Failed to parse response: #{Exception.message(e)}")}
  end

  # Private helpers

  defp encode_forward_backward_input(%ForwardBackwardInput{} = input) do
    %{
      "data" => encode_data(input.data),
      "loss_fn" => encode_loss_fn(input.loss_fn),
      "loss_fn_config" => input.loss_fn_config || %{}
    }
  end

  defp encode_data(data) when is_list(data) do
    Enum.map(data, &encode_datum/1)
  end

  defp encode_datum(%Datum{} = datum) do
    encoded = %{
      "model_input" => encode_model_input(datum.model_input)
    }

    if datum.loss_fn_inputs do
      Map.put(encoded, "loss_fn_inputs", datum.loss_fn_inputs)
    else
      encoded
    end
  end

  defp encode_model_input(%{chunks: _} = model_input) do
    Tinkex.Types.ModelInput.to_ints(model_input)
  end

  defp encode_model_input(tokens) when is_list(tokens), do: tokens

  defp encode_loss_fn(loss_fn) when is_atom(loss_fn) do
    Tinkex.Types.LossFnType.to_string(loss_fn)
  end

  defp encode_loss_fn(loss_fn) when is_binary(loss_fn), do: loss_fn

  defp training_api(%__MODULE__{training_api: nil}), do: TrainingAPI
  defp training_api(%__MODULE__{training_api: api}), do: api

  defp weights_api(%__MODULE__{weights_api: nil}), do: Tinkex.API.Weights
  defp weights_api(%__MODULE__{weights_api: api}), do: api

  defp futures_api(%__MODULE__{futures_api: nil}), do: Future
  defp futures_api(%__MODULE__{futures_api: api}), do: api

  defp models_api(%__MODULE__{models_api: nil}), do: Tinkex.API.Models
  defp models_api(%__MODULE__{models_api: api}), do: api

  # ---------------------------------------------------------------------------
  # Model Management Functions
  # ---------------------------------------------------------------------------

  @doc """
  Fetch model metadata for this training client.

  Used by tokenizer resolution to obtain `model_data.tokenizer_id`.

  ## Examples

      {:ok, info} = TrainingClient.get_info(client)
      info.model_data["tokenizer_id"]
  """
  @spec get_info(t()) :: {:ok, GetInfoResponse.t()} | {:error, Error.t()}
  def get_info(%__MODULE__{} = client) do
    request = %GetInfoRequest{model_id: client.model_id}
    api = models_api(client)
    api.get_info(client.config, request)
  end

  @doc """
  Unload the active model and end the session.

  May return directly or poll a future depending on server response.

  ## Examples

      {:ok, response} = TrainingClient.unload_model(client)
  """
  @spec unload_model(t()) :: {:ok, UnloadModelResponse.t() | map()} | {:error, Error.t()}
  def unload_model(%__MODULE__{} = client) do
    request = %UnloadModelRequest{model_id: client.model_id}
    api = models_api(client)

    case api.unload_model(client.config, request) do
      {:ok, %UnloadModelResponse{} = response} ->
        {:ok, response}

      {:ok, %{"request_id" => request_id}} ->
        poll_and_await_unload(client, request_id)

      {:ok, %{request_id: request_id}} ->
        poll_and_await_unload(client, request_id)

      {:error, error} ->
        {:error, error}
    end
  end

  defp poll_and_await_unload(client, request_id) do
    futures = futures_api(client)
    task = futures.poll(client.config, request_id, [])

    case Task.await(task, :timer.seconds(60)) do
      {:ok, result} ->
        {:ok, UnloadModelResponse.from_json(result)}

      {:error, error} ->
        {:error, error}

      result when is_map(result) ->
        {:ok, UnloadModelResponse.from_json(result)}
    end
  end

  # ---------------------------------------------------------------------------
  # Tokenizer Functions
  # ---------------------------------------------------------------------------

  @doc """
  Get a tokenizer for this training client's model.

  Fetches model info to determine the tokenizer ID, applies heuristics
  (e.g., Llama-3 gating workaround), and loads/caches the tokenizer.

  ## Options

    * `:load_fun` - Custom tokenizer loader function (default: Kimi/HuggingFace)

  ## Examples

      {:ok, tokenizer} = TrainingClient.get_tokenizer(client)
      {:ok, ids} = TrainingClient.encode(client, "Hello world")

  ## Errors

  Returns `{:error, %Tinkex.Error{}}` if:
    * Model info cannot be fetched
    * Tokenizer cannot be loaded
  """
  @spec get_tokenizer(t(), keyword()) ::
          {:ok, Tinkex.Tokenizer.handle()} | {:error, Error.t()}
  def get_tokenizer(%__MODULE__{} = client, opts \\ []) do
    with {:ok, info} <- get_info(client) do
      model_name = get_model_name_from_info(info)
      tokenizer_id = Tinkex.Tokenizer.get_tokenizer_id(model_name, client, opts)
      Tinkex.Tokenizer.get_or_load_tokenizer(tokenizer_id, opts)
    end
  end

  @doc """
  Encode text using this training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.encode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, ids} = TrainingClient.encode(client, "Hello world")

  ## Options

    * `:load_fun` - Custom tokenizer loader function
  """
  @spec encode(t(), String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, Error.t()}
  def encode(%__MODULE__{} = client, text, opts \\ []) when is_binary(text) do
    with {:ok, info} <- get_info(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.encode(text, model_name, opts)
    end
  end

  @doc """
  Decode token IDs using this training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.decode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, text} = TrainingClient.decode(client, [1, 2, 3])

  ## Options

    * `:load_fun` - Custom tokenizer loader function
  """
  @spec decode(t(), [integer()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def decode(%__MODULE__{} = client, ids, opts \\ []) when is_list(ids) do
    with {:ok, info} <- get_info(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.decode(ids, model_name, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Custom Loss Training
  # ---------------------------------------------------------------------------

  @doc """
  Perform forward-backward with a custom loss function.

  This function:
  1. Executes a forward pass to get logprobs for each datum
  2. Computes gradients of the custom loss w.r.t. the logprobs using Nx.Defn.grad
  3. Builds synthetic data with negative gradients as weights
  4. Executes a backward pass with linear_weighted loss

  ## Parameters

    * `client` - TrainingClient instance
    * `data` - List of Datum structs with `loss_fn_inputs["target_tokens"]`
    * `loss_fn` - Function `(data, [Nx.Tensor.t()]) -> {Nx.Tensor.t(), map()}`
                  Takes data and list of logprob tensors, returns (loss, metrics)
    * `opts` - Options (forwarded to forward/backward calls)

  ## Returns

    * `{:ok, Task.t()}` - Task that resolves to ForwardBackwardOutput with merged metrics
    * `{:error, Error.t()}` - Error if request fails

  ## Example

      # Custom entropy loss
      loss_fn = fn _data, logprobs ->
        entropy = logprobs
        |> Enum.map(fn lp ->
          probs = Nx.exp(lp)
          Nx.sum(Nx.multiply(Nx.negate(probs), lp))
        end)
        |> Enum.reduce(&Nx.add/2)

        {entropy, %{"entropy" => Nx.to_number(entropy)}}
      end

      {:ok, task} = TrainingClient.forward_backward_custom(client, data, loss_fn)
      {:ok, output} = Task.await(task)
  """
  @spec forward_backward_custom(t(), [Datum.t()], function(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward_backward_custom(client, data, loss_fn, opts \\ [])

  def forward_backward_custom(%__MODULE__{} = _client, [], _loss_fn, _opts) do
    # Empty data case - return empty metrics
    {:ok, Task.async(fn -> {:ok, %{"loss_fn_output_type" => "custom", "metrics" => %{}}} end)}
  end

  def forward_backward_custom(%__MODULE__{} = client, data, loss_fn, opts) when is_list(data) do
    {:ok,
     Task.async(fn ->
       execute_custom_loss(client, data, loss_fn, opts)
     end)}
  end

  defp execute_custom_loss(client, data, loss_fn, opts) do
    alias Tinkex.Training.CustomLoss

    # Step 1: Forward pass with cross_entropy to get logprobs
    with {:ok, forward_task} <- forward(client, data, opts),
         {:ok, forward_result} <- await_task_result(forward_task),
         forward_output = ForwardBackwardOutput.from_json(forward_result),

         # Step 2: Extract per-datum logprobs
         {:ok, logprobs} <- CustomLoss.extract_per_datum_logprobs(forward_output),

         # Step 3: Compute gradients of custom loss
         {:ok, {gradients, custom_metrics}} <-
           CustomLoss.compute_gradients(data, logprobs, loss_fn),

         # Step 4: Build synthetic data with negative gradients as weights
         linear_data = CustomLoss.build_linear_loss_data(data, gradients),

         # Step 5: Backward pass with linear_weighted loss
         {:ok, backward_task} <-
           forward_backward(client, linear_data, :linear_weighted, opts),
         {:ok, backward_result} <- await_task_result(backward_task) do
      # Step 6: Merge custom metrics into output
      {:ok, merge_custom_metrics(backward_result, custom_metrics)}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Custom loss failed: #{inspect(reason)}")}
    end
  rescue
    e ->
      {:error,
       Error.new(:request_failed, "Custom loss failed: #{Exception.message(e)}",
         exception: e,
         stacktrace: __STACKTRACE__
       )}
  end

  defp await_task_result(task) do
    case Task.await(task, :timer.minutes(5)) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
      result when is_map(result) -> {:ok, result}
    end
  end

  defp merge_custom_metrics(result, custom_metrics) when is_map(result) do
    Map.merge(result, custom_metrics)
  end

  # Extract model name from GetInfoResponse for tokenizer resolution
  defp get_model_name_from_info(%GetInfoResponse{model_data: %{"base_model" => base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%GetInfoResponse{model_data: %{"model_name" => name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(%GetInfoResponse{model_data: %{base_model: base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%GetInfoResponse{model_data: %{model_name: name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(_), do: "unknown"
end
