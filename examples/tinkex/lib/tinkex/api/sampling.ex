defmodule Tinkex.API.Sampling do
  @moduledoc """
  Low-level sampling API operations.

  Provides HTTP endpoints for sampling operations with async/future patterns.
  """

  alias Tinkex.API
  alias Tinkex.Config
  alias Tinkex.Error

  @doc """
  Submit a sample request, returns a future request_id.

  ## Parameters

    * `config` - Tinkex config
    * `request` - Sample request map with keys:
      * `:sampling_session_id` or `:base_model` + `:model_path`
      * `:prompt` - ModelInput or token list
      * `:sampling_params` - SamplingParams struct or map
      * `:seq_id` - Sequence identifier
      * `:num_samples` - Number of samples (default: 1)
      * `:prompt_logprobs` - Whether to return prompt logprobs
      * `:topk_prompt_logprobs` - Top-k prompt logprobs count

  ## Returns

    * `{:ok, %{"request_id" => String.t()}}` - Future request ID
    * `{:error, Error.t()}` - Error response
  """
  @spec sample_future(Config.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def sample_future(%Config{} = config, request) when is_map(request) do
    body = build_sample_request(request)
    http_client = API.client_module(config: config)

    case http_client.post(config, "/v1/sample_future", body) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "sample_future")}
    end
  end

  @doc """
  Submit a logprobs computation request, returns a future request_id.

  ## Parameters

    * `config` - Tinkex config
    * `request` - Logprobs request map with keys:
      * `:sampling_session_id` or `:base_model` + `:model_path`
      * `:prompt` - ModelInput or token list
      * `:seq_id` - Sequence identifier
      * `:topk_logprobs` - Top-k logprobs count (optional)

  ## Returns

    * `{:ok, %{"request_id" => String.t()}}` - Future request ID
    * `{:error, Error.t()}` - Error response
  """
  @spec compute_logprobs_future(Config.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def compute_logprobs_future(%Config{} = config, request) when is_map(request) do
    body = build_logprobs_request(request)
    http_client = API.client_module(config: config)

    case http_client.post(config, "/v1/compute_logprobs_future", body) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, Error.from_response(reason, "compute_logprobs_future")}
    end
  end

  @doc """
  Start a streaming sample request.

  ## Parameters

    * `config` - Tinkex config
    * `request` - Sample request (same as sample_future)

  ## Returns

    * `{:ok, stream}` - SSE event stream
    * `{:error, Error.t()}` - Error response
  """
  @spec sample_stream(Config.t(), map()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
  def sample_stream(%Config{} = config, request) when is_map(request) do
    body = build_sample_request(request)
    http_client = API.client_module(config: config)

    if function_exported?(http_client, :post_stream, 3) do
      case http_client.post_stream(config, "/v1/sample_stream", body) do
        {:ok, stream} -> {:ok, stream}
        {:error, reason} -> {:error, Error.from_response(reason, "sample_stream")}
      end
    else
      {:error, Error.new(:not_supported, "HTTP client does not support streaming")}
    end
  end

  # Build sample request body
  defp build_sample_request(request) do
    request
    |> encode_prompt()
    |> encode_sampling_params()
    |> Map.put("type", "sample")
    |> filter_nil_values()
  end

  # Build logprobs request body
  defp build_logprobs_request(request) do
    request
    |> encode_prompt()
    |> Map.put("type", "compute_logprobs")
    |> filter_nil_values()
  end

  defp encode_prompt(%{prompt: %{chunks: _} = model_input} = req) do
    # ModelInput struct - convert to token list
    tokens = Tinkex.Types.ModelInput.to_ints(model_input)
    Map.put(req, "prompt", tokens) |> Map.delete(:prompt)
  end

  defp encode_prompt(%{prompt: prompt} = req) when is_list(prompt) do
    Map.put(req, "prompt", prompt) |> Map.delete(:prompt)
  end

  defp encode_prompt(%{"prompt" => _} = req), do: req
  defp encode_prompt(req), do: req

  defp encode_sampling_params(%{sampling_params: %{__struct__: _} = params} = req) do
    # Struct - encode to map
    encoded = Map.from_struct(params) |> filter_nil_values()
    Map.put(req, "sampling_params", encoded) |> Map.delete(:sampling_params)
  end

  defp encode_sampling_params(%{sampling_params: params} = req) when is_map(params) do
    Map.put(req, "sampling_params", filter_nil_values(params)) |> Map.delete(:sampling_params)
  end

  defp encode_sampling_params(%{"sampling_params" => _} = req), do: req
  defp encode_sampling_params(req), do: req

  defp filter_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
