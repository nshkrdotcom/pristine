defmodule Tinkex.ServiceClient do
  @moduledoc """
  High-level service client for session management and client creation.

  A struct-based client that manages session lifecycle and creates
  TrainingClient, SamplingClient, and RestClient instances. For production
  use with DynamicSupervisor and telemetry, consider the GenServer-based
  implementation.

  ## Usage

      config = Tinkex.Config.new(api_key: "tml-key")
      client = Tinkex.ServiceClient.new(config)

      # Create a training client
      lora_config = %Tinkex.Types.LoraConfig{rank: 32}
      {:ok, training} = Tinkex.ServiceClient.create_lora_training_client(
        client, "Qwen/Qwen2.5-7B", lora_config
      )

      # Create a sampling client
      {:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(
        client, base_model: "Qwen/Qwen2.5-7B"
      )

      # Create a REST client
      {:ok, rest} = Tinkex.ServiceClient.create_rest_client(client)

  ## Session Management

  The ServiceClient automatically creates a session on initialization unless
  an explicit `:session_id` is provided. All child clients share this session.

  ## Sequence IDs

  Each client type has its own counter for generating deterministic sequence
  IDs, ensuring proper request ordering and traceability.
  """

  alias Tinkex.API.Session, as: SessionAPI
  alias Tinkex.API.Service, as: ServiceAPI
  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.RestClient
  alias Tinkex.SamplingClient
  alias Tinkex.TrainingClient

  alias Tinkex.Types.{
    CreateModelRequest,
    CreateModelResponse,
    CreateSamplingSessionRequest,
    CreateSamplingSessionResponse,
    CreateSessionRequest,
    GetServerCapabilitiesResponse,
    LoraConfig
  }

  @enforce_keys [:session_id, :config]
  defstruct [
    :session_id,
    :config,
    :session_api,
    :service_api,
    :training_counter,
    :sampling_counter
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          config: Config.t(),
          session_api: module() | nil,
          service_api: module() | nil,
          training_counter: reference() | nil,
          sampling_counter: reference() | nil
        }

  @doc """
  Create a new ServiceClient.

  Automatically creates a session with the Tinkex API unless `:session_id`
  is provided.

  ## Options

    * `:session_id` - Explicit session ID (skips session creation)
    * `:session_api` - Module implementing session API (default: `Tinkex.API.Session`)
    * `:service_api` - Module implementing service API (default: `Tinkex.API.Service`)
    * `:tags` - Tags for the session
    * `:user_metadata` - User metadata for the session
  """
  @spec new(Config.t(), keyword()) :: t()
  def new(%Config{} = config, opts \\ []) do
    session_id = resolve_session_id(config, opts)

    %__MODULE__{
      session_id: session_id,
      config: config,
      session_api: Keyword.get(opts, :session_api),
      service_api: Keyword.get(opts, :service_api),
      training_counter: :atomics.new(1, []),
      sampling_counter: :atomics.new(1, [])
    }
  end

  @doc """
  Create a LoRA training client.

  ## Parameters

    * `client` - ServiceClient instance
    * `base_model` - Base model identifier (e.g., "Qwen/Qwen2.5-7B")
    * `lora_config` - LoraConfig struct or nil for defaults
    * `opts` - Additional options:
      * `:user_metadata` - User metadata for the training run

  ## Returns

    * `{:ok, TrainingClient.t()}` - Training client
    * `{:error, Error.t()}` - Error if creation fails
  """
  @spec create_lora_training_client(t(), String.t(), LoraConfig.t() | nil, keyword()) ::
          {:ok, TrainingClient.t()} | {:error, Error.t()}
  def create_lora_training_client(
        %__MODULE__{} = client,
        base_model,
        lora_config,
        opts \\ []
      ) do
    model_seq_id = next_training_seq_id(client)
    lora_config = lora_config || %LoraConfig{}

    request = %CreateModelRequest{
      session_id: client.session_id,
      model_seq_id: model_seq_id,
      base_model: base_model,
      lora_config: lora_config,
      user_metadata: Keyword.get(opts, :user_metadata),
      type: "create_model"
    }

    api = service_api(client)

    case api.create_model(client.config, request) do
      {:ok, %{"model_id" => model_id}} ->
        training_client =
          TrainingClient.new(model_id, client.session_id, client.config, opts)

        {:ok, training_client}

      {:ok, %CreateModelResponse{model_id: model_id}} ->
        training_client =
          TrainingClient.new(model_id, client.session_id, client.config, opts)

        {:ok, training_client}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Create a training client from a checkpoint state.

  ## Parameters

    * `client` - ServiceClient instance
    * `base_model` - Base model identifier
    * `checkpoint_path` - Tinker path to checkpoint
    * `opts` - Additional options:
      * `:include_optimizer` - Load optimizer state (default: false)

  ## Returns

    * `{:ok, TrainingClient.t()}` - Training client
    * `{:error, Error.t()}` - Error if creation fails
  """
  @spec create_training_client_from_state(t(), String.t(), String.t(), keyword()) ::
          {:ok, TrainingClient.t()} | {:error, Error.t()}
  def create_training_client_from_state(
        %__MODULE__{} = client,
        base_model,
        checkpoint_path,
        opts \\ []
      ) do
    # First create the model, then load the checkpoint
    with {:ok, training_client} <- create_lora_training_client(client, base_model, nil, opts),
         {:ok, _loaded} <-
           TrainingClient.load_state(training_client, checkpoint_path, opts) do
      {:ok, training_client}
    end
  end

  @doc """
  Create a sampling client.

  ## Parameters

    * `client` - ServiceClient instance
    * `opts` - Options (one required):
      * `:base_model` - Base model identifier for new sampling session
      * `:model_path` - Tinker path to existing weights

  ## Returns

    * `{:ok, SamplingClient.t()}` - Sampling client
    * `{:error, Error.t()}` - Error if creation fails
  """
  @spec create_sampling_client(t(), keyword()) ::
          {:ok, SamplingClient.t()} | {:error, Error.t()}
  def create_sampling_client(%__MODULE__{} = client, opts \\ []) do
    sampling_seq_id = next_sampling_seq_id(client)
    base_model = Keyword.get(opts, :base_model)
    model_path = Keyword.get(opts, :model_path)

    request = %CreateSamplingSessionRequest{
      session_id: client.session_id,
      sampling_session_seq_id: sampling_seq_id,
      base_model: base_model,
      model_path: model_path,
      type: "create_sampling_session"
    }

    api = service_api(client)

    case api.create_sampling_session(client.config, request) do
      {:ok, %{"sampling_session_id" => sampling_session_id}} ->
        sampling_client =
          SamplingClient.new(sampling_session_id, client.config, opts)

        {:ok, sampling_client}

      {:ok, %CreateSamplingSessionResponse{sampling_session_id: sampling_session_id}} ->
        sampling_client =
          SamplingClient.new(sampling_session_id, client.config, opts)

        {:ok, sampling_client}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Create a REST client.

  ## Parameters

    * `client` - ServiceClient instance

  ## Returns

    * `{:ok, RestClient.t()}` - REST client
  """
  @spec create_rest_client(t()) :: {:ok, RestClient.t()}
  def create_rest_client(%__MODULE__{} = client) do
    rest_client = RestClient.new(client.session_id, client.config)
    {:ok, rest_client}
  end

  @doc """
  Get server capabilities.

  ## Parameters

    * `client` - ServiceClient instance

  ## Returns

    * `{:ok, GetServerCapabilitiesResponse.t()}` - Server capabilities
    * `{:error, Error.t()}` - Error if request fails
  """
  @spec get_server_capabilities(t()) ::
          {:ok, GetServerCapabilitiesResponse.t()} | {:error, Error.t()}
  def get_server_capabilities(%__MODULE__{} = client) do
    api = service_api(client)

    case api.get_server_capabilities(client.config) do
      {:ok, response} ->
        {:ok, GetServerCapabilitiesResponse.from_json(response)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get the session ID.
  """
  @spec session_id(t()) :: String.t()
  def session_id(%__MODULE__{session_id: id}), do: id

  @doc """
  Get the config.
  """
  @spec config(t()) :: Config.t()
  def config(%__MODULE__{config: config}), do: config

  @doc """
  Get the next training sequence ID.
  """
  @spec next_training_seq_id(t()) :: integer()
  def next_training_seq_id(%__MODULE__{training_counter: counter}) do
    :atomics.add_get(counter, 1, 1)
  end

  @doc """
  Get the next sampling sequence ID.
  """
  @spec next_sampling_seq_id(t()) :: integer()
  def next_sampling_seq_id(%__MODULE__{sampling_counter: counter}) do
    :atomics.add_get(counter, 1, 1)
  end

  # Private helpers

  defp resolve_session_id(config, opts) do
    case Keyword.get(opts, :session_id) do
      nil -> create_session(config, opts)
      session_id -> session_id
    end
  end

  defp create_session(config, opts) do
    api = Keyword.get(opts, :session_api, SessionAPI)

    request = %CreateSessionRequest{
      tags: Keyword.get(opts, :tags),
      user_metadata: Keyword.get(opts, :user_metadata),
      sdk_version: "tinkex-elixir-0.1.0",
      type: "create_session"
    }

    case api.create(config, request) do
      {:ok, %{"session_id" => session_id}} ->
        session_id

      {:ok, %{session_id: session_id}} ->
        session_id

      {:error, error} ->
        raise "Failed to create session: #{inspect(error)}"
    end
  end

  defp service_api(%__MODULE__{service_api: nil}), do: ServiceAPI
  defp service_api(%__MODULE__{service_api: api}), do: api
end
