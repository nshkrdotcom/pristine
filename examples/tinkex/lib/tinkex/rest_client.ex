defmodule Tinkex.RestClient do
  @moduledoc """
  High-level REST client for session, checkpoint, and training run management.

  A struct-based client that wraps `Tinkex.API.Rest` with typed responses
  and convenient session management.

  ## Usage

      config = Tinkex.Config.new(api_key: "tml-key")
      client = Tinkex.RestClient.new("session-123", config)

      # List training runs
      {:ok, runs} = Tinkex.RestClient.list_training_runs(client)

      # Get checkpoint info
      {:ok, checkpoints} = Tinkex.RestClient.list_checkpoints(client, "run-id")

  ## Async Operations

  All synchronous functions have `_async` variants that return `Task.t()`:

      task = Tinkex.RestClient.list_training_runs_async(client)
      {:ok, runs} = Task.await(task)
  """

  alias Tinkex.API.Rest
  alias Tinkex.Config

  alias Tinkex.Types.{
    CheckpointArchiveUrlResponse,
    CheckpointsListResponse,
    GetSamplerResponse,
    GetSessionResponse,
    ListSessionsResponse,
    TrainingRun,
    TrainingRunsResponse,
    WeightsInfoResponse
  }

  @enforce_keys [:session_id, :config]
  defstruct [:session_id, :config, :rest_api]

  @type t :: %__MODULE__{
          session_id: String.t(),
          config: Config.t(),
          rest_api: module() | nil
        }

  @doc """
  Create a new RestClient.

  ## Options

    * `:rest_api` - Module implementing REST API functions (default: `Tinkex.API.Rest`)
  """
  @spec new(String.t(), Config.t(), keyword()) :: t()
  def new(session_id, config, opts \\ []) do
    %__MODULE__{
      session_id: session_id,
      config: config,
      rest_api: Keyword.get(opts, :rest_api)
    }
  end

  # Session APIs

  @doc """
  Get session information.
  """
  @spec get_session(t(), String.t()) ::
          {:ok, GetSessionResponse.t()} | {:error, Tinkex.Error.t()}
  def get_session(%__MODULE__{} = client, session_id) do
    case rest_api(client).get_session(client.config, session_id) do
      {:ok, data} -> {:ok, GetSessionResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  List sessions.

  ## Options

    * `:limit` - Maximum number of sessions to return (default: 20)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_sessions(t(), keyword()) ::
          {:ok, ListSessionsResponse.t()} | {:error, Tinkex.Error.t()}
  def list_sessions(%__MODULE__{} = client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    case rest_api(client).list_sessions(client.config, limit, offset) do
      {:ok, data} -> {:ok, ListSessionsResponse.from_map(data)}
      error -> error
    end
  end

  # Checkpoint APIs

  @doc """
  List checkpoints for a training run.
  """
  @spec list_checkpoints(t(), String.t()) ::
          {:ok, CheckpointsListResponse.t()} | {:error, Tinkex.Error.t()}
  def list_checkpoints(%__MODULE__{} = client, run_id) do
    case rest_api(client).list_checkpoints(client.config, run_id) do
      {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  List all user checkpoints.

  ## Options

    * `:limit` - Maximum number of checkpoints to return (default: 100)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_user_checkpoints(t(), keyword()) ::
          {:ok, CheckpointsListResponse.t()} | {:error, Tinkex.Error.t()}
  def list_user_checkpoints(%__MODULE__{} = client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    case rest_api(client).list_user_checkpoints(client.config, limit, offset) do
      {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  Get checkpoint archive download URL by tinker path.
  """
  @spec get_checkpoint_archive_url(t(), String.t()) ::
          {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(%__MODULE__{} = client, tinker_path)
      when is_binary(tinker_path) do
    case rest_api(client).get_checkpoint_archive_url(client.config, tinker_path) do
      {:ok, data} -> {:ok, CheckpointArchiveUrlResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  Get checkpoint archive download URL by run_id and checkpoint_id.
  """
  @spec get_checkpoint_archive_url(t(), String.t(), String.t()) ::
          {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(%__MODULE__{} = client, run_id, checkpoint_id) do
    case rest_api(client).get_checkpoint_archive_url(client.config, run_id, checkpoint_id) do
      {:ok, data} -> {:ok, CheckpointArchiveUrlResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  Delete a checkpoint by tinker path.
  """
  @spec delete_checkpoint(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(%__MODULE__{} = client, tinker_path) when is_binary(tinker_path) do
    rest_api(client).delete_checkpoint(client.config, tinker_path)
  end

  @doc """
  Delete a checkpoint by run_id and checkpoint_id.
  """
  @spec delete_checkpoint(t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(%__MODULE__{} = client, run_id, checkpoint_id) do
    rest_api(client).delete_checkpoint(client.config, run_id, checkpoint_id)
  end

  @doc """
  Publish a checkpoint to make it public.
  """
  @spec publish_checkpoint(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def publish_checkpoint(%__MODULE__{} = client, tinker_path) do
    rest_api(client).publish_checkpoint(client.config, tinker_path)
  end

  @doc """
  Unpublish a checkpoint to make it private.
  """
  @spec unpublish_checkpoint(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def unpublish_checkpoint(%__MODULE__{} = client, tinker_path) do
    rest_api(client).unpublish_checkpoint(client.config, tinker_path)
  end

  # Training Run APIs

  @doc """
  Get training run by ID.
  """
  @spec get_training_run(t(), String.t()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run(%__MODULE__{} = client, training_run_id) do
    rest_api(client).get_training_run(client.config, training_run_id)
  end

  @doc """
  Get training run by tinker path.
  """
  @spec get_training_run_by_tinker_path(t(), String.t()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run_by_tinker_path(%__MODULE__{} = client, tinker_path) do
    rest_api(client).get_training_run_by_tinker_path(client.config, tinker_path)
  end

  @doc """
  List training runs.

  ## Options

    * `:limit` - Maximum number of training runs to return (default: 20)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_training_runs(t(), keyword()) ::
          {:ok, TrainingRunsResponse.t()} | {:error, Tinkex.Error.t()}
  def list_training_runs(%__MODULE__{} = client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    rest_api(client).list_training_runs(client.config, limit, offset)
  end

  # Sampler/Weights APIs

  @doc """
  Get sampler information.
  """
  @spec get_sampler(t(), String.t()) ::
          {:ok, GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
  def get_sampler(%__MODULE__{} = client, sampler_id) do
    rest_api(client).get_sampler(client.config, sampler_id)
  end

  @doc """
  Get weights information by tinker path.
  """
  @spec get_weights_info_by_tinker_path(t(), String.t()) ::
          {:ok, WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_weights_info_by_tinker_path(%__MODULE__{} = client, tinker_path) do
    rest_api(client).get_weights_info_by_tinker_path(client.config, tinker_path)
  end

  # Async variants

  @doc """
  Async variant of `get_session/2`.
  """
  @spec get_session_async(t(), String.t()) :: Task.t()
  def get_session_async(client, session_id) do
    Task.async(fn -> get_session(client, session_id) end)
  end

  @doc """
  Async variant of `list_sessions/2`.
  """
  @spec list_sessions_async(t(), keyword()) :: Task.t()
  def list_sessions_async(client, opts \\ []) do
    Task.async(fn -> list_sessions(client, opts) end)
  end

  @doc """
  Async variant of `list_checkpoints/2`.
  """
  @spec list_checkpoints_async(t(), String.t()) :: Task.t()
  def list_checkpoints_async(client, run_id) do
    Task.async(fn -> list_checkpoints(client, run_id) end)
  end

  @doc """
  Async variant of `list_user_checkpoints/2`.
  """
  @spec list_user_checkpoints_async(t(), keyword()) :: Task.t()
  def list_user_checkpoints_async(client, opts \\ []) do
    Task.async(fn -> list_user_checkpoints(client, opts) end)
  end

  @doc """
  Async variant of `get_checkpoint_archive_url/2`.
  """
  @spec get_checkpoint_archive_url_async(t(), String.t()) :: Task.t()
  def get_checkpoint_archive_url_async(client, tinker_path) when is_binary(tinker_path) do
    Task.async(fn -> get_checkpoint_archive_url(client, tinker_path) end)
  end

  @doc """
  Async variant of `get_checkpoint_archive_url/3`.
  """
  @spec get_checkpoint_archive_url_async(t(), String.t(), String.t()) :: Task.t()
  def get_checkpoint_archive_url_async(client, run_id, checkpoint_id) do
    Task.async(fn -> get_checkpoint_archive_url(client, run_id, checkpoint_id) end)
  end

  @doc """
  Async variant of `delete_checkpoint/2`.
  """
  @spec delete_checkpoint_async(t(), String.t()) :: Task.t()
  def delete_checkpoint_async(client, tinker_path) when is_binary(tinker_path) do
    Task.async(fn -> delete_checkpoint(client, tinker_path) end)
  end

  @doc """
  Async variant of `delete_checkpoint/3`.
  """
  @spec delete_checkpoint_async(t(), String.t(), String.t()) :: Task.t()
  def delete_checkpoint_async(client, run_id, checkpoint_id) do
    Task.async(fn -> delete_checkpoint(client, run_id, checkpoint_id) end)
  end

  @doc """
  Async variant of `publish_checkpoint/2`.
  """
  @spec publish_checkpoint_async(t(), String.t()) :: Task.t()
  def publish_checkpoint_async(client, tinker_path) do
    Task.async(fn -> publish_checkpoint(client, tinker_path) end)
  end

  @doc """
  Async variant of `unpublish_checkpoint/2`.
  """
  @spec unpublish_checkpoint_async(t(), String.t()) :: Task.t()
  def unpublish_checkpoint_async(client, tinker_path) do
    Task.async(fn -> unpublish_checkpoint(client, tinker_path) end)
  end

  @doc """
  Async variant of `get_training_run/2`.
  """
  @spec get_training_run_async(t(), String.t()) :: Task.t()
  def get_training_run_async(client, training_run_id) do
    Task.async(fn -> get_training_run(client, training_run_id) end)
  end

  @doc """
  Async variant of `get_training_run_by_tinker_path/2`.
  """
  @spec get_training_run_by_tinker_path_async(t(), String.t()) :: Task.t()
  def get_training_run_by_tinker_path_async(client, tinker_path) do
    Task.async(fn -> get_training_run_by_tinker_path(client, tinker_path) end)
  end

  @doc """
  Async variant of `list_training_runs/2`.
  """
  @spec list_training_runs_async(t(), keyword()) :: Task.t()
  def list_training_runs_async(client, opts \\ []) do
    Task.async(fn -> list_training_runs(client, opts) end)
  end

  @doc """
  Async variant of `get_sampler/2`.
  """
  @spec get_sampler_async(t(), String.t()) :: Task.t()
  def get_sampler_async(client, sampler_id) do
    Task.async(fn -> get_sampler(client, sampler_id) end)
  end

  @doc """
  Async variant of `get_weights_info_by_tinker_path/2`.
  """
  @spec get_weights_info_by_tinker_path_async(t(), String.t()) :: Task.t()
  def get_weights_info_by_tinker_path_async(client, tinker_path) do
    Task.async(fn -> get_weights_info_by_tinker_path(client, tinker_path) end)
  end

  # ============================================
  # Convenience Aliases (Python SDK Parity)
  # ============================================

  @doc """
  Delete a checkpoint by tinker path.

  Alias for `delete_checkpoint/2` to mirror Python SDK convenience naming.
  """
  @spec delete_checkpoint_by_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint_by_tinker_path(client, checkpoint_path) do
    delete_checkpoint(client, checkpoint_path)
  end

  @doc """
  Publish a checkpoint by tinker path.

  Alias for `publish_checkpoint/2` to mirror Python SDK convenience naming.
  """
  @spec publish_checkpoint_from_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def publish_checkpoint_from_tinker_path(client, checkpoint_path) do
    publish_checkpoint(client, checkpoint_path)
  end

  @doc """
  Unpublish a checkpoint by tinker path.

  Alias for `unpublish_checkpoint/2` to mirror Python SDK convenience naming.
  """
  @spec unpublish_checkpoint_from_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def unpublish_checkpoint_from_tinker_path(client, checkpoint_path) do
    unpublish_checkpoint(client, checkpoint_path)
  end

  @doc """
  Get checkpoint archive URL by tinker path.

  Alias for `get_checkpoint_archive_url/2` to mirror Python SDK convenience naming.
  """
  @spec get_checkpoint_archive_url_by_tinker_path(t(), String.t()) ::
          {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url_by_tinker_path(client, checkpoint_path) do
    get_checkpoint_archive_url(client, checkpoint_path)
  end

  # Async variants of aliases

  @doc """
  Async variant of `delete_checkpoint_by_tinker_path/2`.
  """
  @spec delete_checkpoint_by_tinker_path_async(t(), String.t()) :: Task.t()
  def delete_checkpoint_by_tinker_path_async(client, checkpoint_path) do
    delete_checkpoint_async(client, checkpoint_path)
  end

  @doc """
  Async variant of `publish_checkpoint_from_tinker_path/2`.
  """
  @spec publish_checkpoint_from_tinker_path_async(t(), String.t()) :: Task.t()
  def publish_checkpoint_from_tinker_path_async(client, checkpoint_path) do
    publish_checkpoint_async(client, checkpoint_path)
  end

  @doc """
  Async variant of `unpublish_checkpoint_from_tinker_path/2`.
  """
  @spec unpublish_checkpoint_from_tinker_path_async(t(), String.t()) :: Task.t()
  def unpublish_checkpoint_from_tinker_path_async(client, checkpoint_path) do
    unpublish_checkpoint_async(client, checkpoint_path)
  end

  @doc """
  Async variant of `get_checkpoint_archive_url_by_tinker_path/2`.
  """
  @spec get_checkpoint_archive_url_by_tinker_path_async(t(), String.t()) :: Task.t()
  def get_checkpoint_archive_url_by_tinker_path_async(client, checkpoint_path) do
    get_checkpoint_archive_url_async(client, checkpoint_path)
  end

  # Private helpers

  defp rest_api(%__MODULE__{rest_api: nil}), do: Rest
  defp rest_api(%__MODULE__{rest_api: api}), do: api
end
