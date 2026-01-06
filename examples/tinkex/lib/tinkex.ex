defmodule Tinkex do
  @moduledoc """
  Tinkex - Elixir SDK for the Tinker ML Training Platform.

  This SDK provides a high-level interface for interacting with the Tinker API,
  enabling model fine-tuning, inference, and checkpoint management.

  ## Quick Start

      # Create a service client (starts a session)
      client = Tinkex.new(api_key: "tml-your-api-key")

      # Create a training client for fine-tuning
      {:ok, trainer} = Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B")

      # Create a sampling client for inference
      {:ok, sampler} = Tinkex.create_sampling_client(client, base_model: "Qwen/Qwen2.5-7B")

      # Create a REST client for checkpoint management
      {:ok, rest} = Tinkex.create_rest_client(client)

  ## Architecture

  The SDK follows a hierarchical client pattern:

  - **ServiceClient** - Top-level orchestrator that manages sessions and creates
    other clients. Use `Tinkex.new/1` to create one.

  - **TrainingClient** - Handles model training operations: forward/backward passes,
    optimizer steps, checkpoint saving/loading.

  - **SamplingClient** - Handles text generation: sampling, streaming, logprobs.

  - **RestClient** - Handles REST operations: checkpoint listing, session management,
    training run queries.

  ## Configuration

  All options can be passed to `Tinkex.new/1`:

  - `:api_key` - Required. Your Tinker API key (must start with "tml-")
  - `:base_url` - API base URL (default: production endpoint)
  - `:timeout` - Request timeout in ms (default: 60_000)
  - `:max_retries` - Max retry attempts (default: 3)
  - `:session_id` - Explicit session ID (skips session creation)
  - `:tags` - Tags for the session
  - `:user_metadata` - Custom metadata

  ## Examples

  ### Basic Training Loop

      client = Tinkex.new(api_key: System.get_env("TINKER_API_KEY"))

      {:ok, trainer} = Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B",
        lora_config: %Tinkex.Types.LoraConfig{rank: 32}
      )

      adam = %Tinkex.Types.AdamParams{learning_rate: 0.0001}

      for batch <- training_data do
        {:ok, task} = Tinkex.TrainingClient.forward_backward(trainer, batch, :cross_entropy)
        {:ok, output} = Task.await(task)
        IO.puts("Loss: \#{output["metrics"]["loss"]}")

        {:ok, task} = Tinkex.TrainingClient.optim_step(trainer, adam)
        Task.await(task)
      end

      Tinkex.TrainingClient.save_state(trainer, "final-checkpoint")

  ### Inference with Streaming

      client = Tinkex.new(api_key: System.get_env("TINKER_API_KEY"))

      {:ok, sampler} = Tinkex.create_sampling_client(client,
        model_path: "tinker://run-123/weights/checkpoint"
      )

      prompt = Tinkex.Types.ModelInput.from_ints([1, 2, 3])
      params = %Tinkex.Types.SamplingParams{max_tokens: 100, temperature: 0.7}

      {:ok, stream} = Tinkex.SamplingClient.sample_stream(sampler, prompt, params)

      Enum.each(stream, fn event ->
        IO.write(event["token"])
      end)
  """

  alias Tinkex.Config
  alias Tinkex.ServiceClient

  @version "0.1.0"

  @doc """
  Create a new Tinkex service client.

  This is the main entrypoint for the SDK. It creates a session with the
  Tinker API (unless `:session_id` is provided) and returns a ServiceClient
  that can be used to create other clients.

  ## Options

  - `:api_key` - Required. Your Tinker API key (must start with "tml-")
  - `:base_url` - API base URL
  - `:timeout` - Request timeout in ms
  - `:max_retries` - Max retry attempts
  - `:session_id` - Explicit session ID (skips session creation)
  - `:tags` - Tags for the session
  - `:user_metadata` - Custom metadata
  - `:session_api` - Custom session API module (for testing)
  - `:service_api` - Custom service API module (for testing)

  ## Examples

      # Basic usage
      client = Tinkex.new(api_key: "tml-your-key")

      # With custom config
      client = Tinkex.new(
        api_key: "tml-your-key",
        base_url: "https://custom.endpoint.com",
        timeout: 120_000
      )

      # With explicit session
      client = Tinkex.new(
        api_key: "tml-your-key",
        session_id: "existing-session-id"
      )
  """
  @spec new(keyword()) :: ServiceClient.t()
  def new(opts \\ []) do
    config = Config.new(opts)
    ServiceClient.new(config, opts)
  end

  @doc """
  Create a new Tinkex service client, raising on error.

  Same as `new/1` but raises if the session cannot be created.
  """
  @spec new!(keyword()) :: ServiceClient.t()
  def new!(opts \\ []) do
    new(opts)
  end

  @doc """
  Create a training client for model fine-tuning.

  Delegates to `Tinkex.ServiceClient.create_lora_training_client/4`.

  ## Parameters

  - `client` - ServiceClient from `Tinkex.new/1`
  - `base_model` - Base model identifier (e.g., "Qwen/Qwen2.5-7B")
  - `opts` - Options:
    - `:lora_config` - LoraConfig struct for LoRA hyperparameters
    - `:user_metadata` - Custom metadata

  ## Examples

      {:ok, trainer} = Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B")

      {:ok, trainer} = Tinkex.create_training_client(client, "Qwen/Qwen2.5-7B",
        lora_config: %Tinkex.Types.LoraConfig{rank: 64}
      )
  """
  @spec create_training_client(ServiceClient.t(), String.t(), keyword()) ::
          {:ok, Tinkex.TrainingClient.t()} | {:error, Tinkex.Error.t()}
  def create_training_client(client, base_model, opts \\ []) do
    lora_config = Keyword.get(opts, :lora_config)
    ServiceClient.create_lora_training_client(client, base_model, lora_config, opts)
  end

  @doc """
  Create a sampling client for text generation.

  Delegates to `Tinkex.ServiceClient.create_sampling_client/2`.

  ## Parameters

  - `client` - ServiceClient from `Tinkex.new/1`
  - `opts` - Options (one required):
    - `:base_model` - Base model for new sampling session
    - `:model_path` - Tinker path to existing weights

  ## Examples

      {:ok, sampler} = Tinkex.create_sampling_client(client, base_model: "Qwen/Qwen2.5-7B")

      {:ok, sampler} = Tinkex.create_sampling_client(client,
        model_path: "tinker://run-123/weights/checkpoint"
      )
  """
  @spec create_sampling_client(ServiceClient.t(), keyword()) ::
          {:ok, Tinkex.SamplingClient.t()} | {:error, Tinkex.Error.t()}
  def create_sampling_client(client, opts \\ []) do
    ServiceClient.create_sampling_client(client, opts)
  end

  @doc """
  Create a REST client for checkpoint and session management.

  Delegates to `Tinkex.ServiceClient.create_rest_client/1`.

  ## Parameters

  - `client` - ServiceClient from `Tinkex.new/1`

  ## Examples

      {:ok, rest} = Tinkex.create_rest_client(client)

      # List checkpoints
      {:ok, response} = Tinkex.RestClient.list_user_checkpoints(rest)
  """
  @spec create_rest_client(ServiceClient.t()) :: {:ok, Tinkex.RestClient.t()}
  def create_rest_client(client) do
    ServiceClient.create_rest_client(client)
  end

  @doc """
  Get server capabilities (supported models, features).

  Delegates to `Tinkex.ServiceClient.get_server_capabilities/1`.

  ## Parameters

  - `client` - ServiceClient from `Tinkex.new/1`

  ## Examples

      {:ok, caps} = Tinkex.get_server_capabilities(client)
      IO.inspect(caps.supported_models)
  """
  @spec get_server_capabilities(ServiceClient.t()) ::
          {:ok, Tinkex.Types.GetServerCapabilitiesResponse.t()} | {:error, Tinkex.Error.t()}
  def get_server_capabilities(client) do
    ServiceClient.get_server_capabilities(client)
  end

  @doc """
  Get the SDK version.

  ## Examples

      Tinkex.version()
      #=> "0.1.0"
  """
  @spec version() :: String.t()
  def version, do: @version
end
