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
    :sampling_counter,
    :telemetry_reporter
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          config: Config.t(),
          session_api: module() | nil,
          service_api: module() | nil,
          training_counter: reference() | nil,
          sampling_counter: reference() | nil,
          telemetry_reporter: pid() | nil
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
    * `:telemetry_enabled` - Start a telemetry reporter (default: from config)
    * `:telemetry_reporter` - Existing reporter pid to use
  """
  @spec new(Config.t(), keyword()) :: t()
  def new(%Config{} = config, opts \\ []) do
    session_id = resolve_session_id(config, opts)
    reporter = resolve_telemetry_reporter(config, session_id, opts)

    %__MODULE__{
      session_id: session_id,
      config: config,
      session_api: Keyword.get(opts, :session_api),
      service_api: Keyword.get(opts, :service_api),
      training_counter: :atomics.new(1, []),
      sampling_counter: :atomics.new(1, []),
      telemetry_reporter: reporter
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

  # ============================================
  # Async Wrappers
  # ============================================

  @doc """
  Get server capabilities asynchronously.

  Returns a Task that resolves to `{:ok, GetServerCapabilitiesResponse.t()}` or
  `{:error, Error.t()}`.

  ## Example

      task = ServiceClient.get_server_capabilities_async(client)
      # Do other work...
      {:ok, capabilities} = Task.await(task)
  """
  @spec get_server_capabilities_async(t()) :: Task.t()
  def get_server_capabilities_async(%__MODULE__{} = client) do
    Task.async(fn -> get_server_capabilities(client) end)
  end

  @doc """
  Create a LoRA training client asynchronously.

  Returns a Task that resolves to `{:ok, TrainingClient.t()}` or
  `{:error, Error.t()}`.

  ## Example

      task = ServiceClient.create_lora_training_client_async(client, "model", config)
      # Do other work...
      {:ok, training_client} = Task.await(task)
  """
  @spec create_lora_training_client_async(t(), String.t(), LoraConfig.t() | nil, keyword()) ::
          Task.t()
  def create_lora_training_client_async(
        %__MODULE__{} = client,
        base_model,
        lora_config,
        opts \\ []
      ) do
    Task.async(fn -> create_lora_training_client(client, base_model, lora_config, opts) end)
  end

  @doc """
  Create a training client from checkpoint state asynchronously.

  Returns a Task that resolves to `{:ok, TrainingClient.t()}` or
  `{:error, Error.t()}`.

  ## Example

      task = ServiceClient.create_training_client_from_state_async(
        client, "model", "tinker://path/to/checkpoint"
      )
      {:ok, training_client} = Task.await(task)
  """
  @spec create_training_client_from_state_async(t(), String.t(), String.t(), keyword()) ::
          Task.t()
  def create_training_client_from_state_async(
        %__MODULE__{} = client,
        base_model,
        checkpoint_path,
        opts \\ []
      ) do
    Task.async(fn ->
      create_training_client_from_state(client, base_model, checkpoint_path, opts)
    end)
  end

  @doc """
  Create a sampling client asynchronously.

  Returns a Task that resolves to `{:ok, SamplingClient.t()}` or
  `{:error, Error.t()}`.

  ## Example

      task = ServiceClient.create_sampling_client_async(client, base_model: "model")
      {:ok, sampling_client} = Task.await(task)
  """
  @spec create_sampling_client_async(t(), keyword()) :: Task.t()
  def create_sampling_client_async(%__MODULE__{} = client, opts \\ []) do
    Task.async(fn -> create_sampling_client(client, opts) end)
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

  defp resolve_telemetry_reporter(config, session_id, opts) do
    case Keyword.get(opts, :telemetry_reporter) do
      nil ->
        # Check if we should start a new reporter
        enabled? =
          case Keyword.get(opts, :telemetry_enabled) do
            nil -> config.telemetry_enabled?
            value -> value
          end

        if enabled? do
          case Tinkex.Telemetry.Reporter.start_link(
                 config: config,
                 session_id: session_id,
                 enabled: true
               ) do
            {:ok, pid} -> pid
            :ignore -> nil
            {:error, _} -> nil
          end
        else
          nil
        end

      reporter when is_pid(reporter) ->
        reporter
    end
  end

  # ============================================
  # Telemetry
  # ============================================

  @doc """
  Get the telemetry reporter for this client.

  Returns the reporter pid if telemetry is enabled and a reporter was started,
  otherwise returns `nil`.

  ## Examples

      reporter = ServiceClient.telemetry_reporter(client)
      if reporter do
        Tinkex.Telemetry.Reporter.log(reporter, "custom.event", %{data: "value"})
      end

  """
  @spec telemetry_reporter(t()) :: pid() | nil
  def telemetry_reporter(%__MODULE__{telemetry_reporter: reporter}), do: reporter

  @doc """
  Get telemetry statistics for this client.

  Returns a map containing telemetry stats for the client's session,
  or `nil` if no reporter is active.

  ## Stats returned

    * `:session_id` - The session ID
    * `:reporter_alive?` - Whether the reporter process is alive
    * `:reporter_pid` - The reporter pid (if active)

  ## Examples

      case ServiceClient.get_telemetry(client) do
        nil ->
          IO.puts("Telemetry not enabled")

        stats ->
          IO.puts("Reporter alive: \#{stats.reporter_alive?}")
      end

  """
  @spec get_telemetry(t()) :: map() | nil
  def get_telemetry(%__MODULE__{telemetry_reporter: nil}), do: nil

  def get_telemetry(%__MODULE__{} = client) do
    reporter = client.telemetry_reporter

    %{
      session_id: client.session_id,
      reporter_alive?: Process.alive?(reporter),
      reporter_pid: reporter
    }
  end

  @doc """
  Get global telemetry statistics.

  Returns summary statistics about telemetry across all active sessions.
  This is a convenience function for observability dashboards.

  Note: In the struct-based client architecture, this returns basic
  global information. For full telemetry aggregation, use the Telemetry
  module directly.

  ## Examples

      stats = ServiceClient.get_telemetry()
      IO.puts("Telemetry system status: \#{stats.status}")

  """
  @spec get_telemetry() :: map()
  def get_telemetry do
    %{
      status: :active,
      sdk_version: Tinkex.version(),
      timestamp: DateTime.utc_now()
    }
  end
end
