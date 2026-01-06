defmodule Tinkex.API.Weights do
  @moduledoc """
  Low-level weights/checkpoint API operations.

  Provides HTTP endpoints for saving and loading model weights and checkpoints.
  """

  alias Tinkex.API
  alias Tinkex.Config
  alias Tinkex.Error

  alias Tinkex.Types.{
    LoadWeightsRequest,
    SaveWeightsForSamplerRequest,
    SaveWeightsRequest
  }

  @doc """
  Save model weights to a checkpoint.

  ## Parameters

    * `config` - Tinkex config
    * `request` - SaveWeightsRequest struct

  ## Returns

    * `{:ok, map()}` - Response with checkpoint path and type
    * `{:error, Error.t()}` - Error response
  """
  @spec save_weights(Config.t(), SaveWeightsRequest.t() | map()) ::
          {:ok, map()} | {:error, Error.t()}
  def save_weights(%Config{} = config, %SaveWeightsRequest{} = request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/save_weights", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "save_weights")}
    end
  end

  def save_weights(%Config{} = config, request) when is_map(request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/save_weights", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "save_weights")}
    end
  end

  @doc """
  Load model weights from a checkpoint.

  ## Parameters

    * `config` - Tinkex config
    * `request` - LoadWeightsRequest struct

  ## Returns

    * `{:ok, map()}` - Response with loaded path and type
    * `{:error, Error.t()}` - Error response
  """
  @spec load_weights(Config.t(), LoadWeightsRequest.t() | map()) ::
          {:ok, map()} | {:error, Error.t()}
  def load_weights(%Config{} = config, %LoadWeightsRequest{} = request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/load_weights", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "load_weights")}
    end
  end

  def load_weights(%Config{} = config, request) when is_map(request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/load_weights", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "load_weights")}
    end
  end

  @doc """
  Save model weights for use with a sampling client.

  ## Parameters

    * `config` - Tinkex config
    * `request` - SaveWeightsForSamplerRequest struct

  ## Returns

    * `{:ok, map()}` - Response with path and sampling_session_id
    * `{:error, Error.t()}` - Error response
  """
  @spec save_weights_for_sampler(Config.t(), SaveWeightsForSamplerRequest.t() | map()) ::
          {:ok, map()} | {:error, Error.t()}
  def save_weights_for_sampler(%Config{} = config, %SaveWeightsForSamplerRequest{} = request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/save_weights_for_sampler", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "save_weights_for_sampler")}
    end
  end

  def save_weights_for_sampler(%Config{} = config, request) when is_map(request) do
    body = Jason.encode!(request)
    http_client = API.client_module(config: config)

    case http_client.post("/v1/save_weights_for_sampler", body, config: config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "save_weights_for_sampler")}
    end
  end
end
