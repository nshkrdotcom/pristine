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
    LoadWeightsRequest,
    LoadWeightsResponse,
    OptimStepRequest,
    OptimStepResponse,
    SaveWeightsForSamplerRequest,
    SaveWeightsForSamplerResponse,
    SaveWeightsRequest,
    SaveWeightsResponse
  }

  @enforce_keys [:model_id, :session_id, :config]
  defstruct [
    :model_id,
    :session_id,
    :config,
    :training_api,
    :weights_api,
    :futures_api,
    :seq_counter
  ]

  @type t :: %__MODULE__{
          model_id: String.t(),
          session_id: String.t(),
          config: Config.t(),
          training_api: module() | nil,
          weights_api: module() | nil,
          futures_api: module() | nil,
          seq_counter: reference() | nil
        }

  @doc """
  Create a new TrainingClient.

  ## Options

    * `:training_api` - Module implementing training API (default: `Tinkex.API.Training`)
    * `:weights_api` - Module implementing weights API (default: `Tinkex.API.Weights`)
    * `:futures_api` - Module implementing futures polling (default: `Tinkex.Future`)
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
end
