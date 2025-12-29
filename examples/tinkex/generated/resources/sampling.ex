defmodule Tinkex.Sampling do
  @moduledoc """
  Sampling resource endpoints.

  This module provides functions for interacting with sampling resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(%{context: Pristine.Core.Context.t()}) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  Create a new sample from a model
  ## Parameters
    * `model` - Required parameter.
    * `prompt` - Required parameter.
    * `opts` - Optional parameters:
      * `:max_tokens` - Optional parameter.
      * `:metadata` - Optional parameter.
      * `:stop_sequences` - Optional parameter.
      * `:stream` - Optional parameter.
      * `:temperature` - Optional parameter.
      * `:top_p` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_sample(model, prompt, [])
  """
  @spec create_sample(t(), String.t(), String.t(), keyword()) ::
          {:ok, Tinkex.Types.SampleResult.t()} | {:error, Pristine.Error.t()}
  def create_sample(%__MODULE__{context: context}, model, prompt, opts \\ []) do
    payload =
      %{
        "model" => model,
        "prompt" => prompt
      }
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> maybe_put("metadata", Keyword.get(opts, :metadata))
      |> maybe_put("stop_sequences", Keyword.get(opts, :stop_sequences))
      |> maybe_put("stream", Keyword.get(opts, :stream))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("top_p", Keyword.get(opts, :top_p))

    Pristine.Core.Pipeline.execute(
      Tinkex.Client.manifest(),
      "create_sample",
      payload,
      context,
      opts
    )
  end

  @doc """
  Create a sample asynchronously, returns a future
  ## Parameters
    * `model` - Required parameter.
    * `prompt` - Required parameter.
    * `opts` - Optional parameters:
      * `:max_tokens` - Optional parameter.
      * `:metadata` - Optional parameter.
      * `:stop_sequences` - Optional parameter.
      * `:stream` - Optional parameter.
      * `:temperature` - Optional parameter.
      * `:top_p` - Optional parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_sample_async(model, prompt, [])
  """
  @spec create_sample_async(t(), String.t(), String.t(), keyword()) ::
          {:ok, Tinkex.Types.AsyncSampleResponse.t()} | {:error, Pristine.Error.t()}
  def create_sample_async(%__MODULE__{context: context}, model, prompt, opts \\ []) do
    payload =
      %{
        "model" => model,
        "prompt" => prompt
      }
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> maybe_put("metadata", Keyword.get(opts, :metadata))
      |> maybe_put("stop_sequences", Keyword.get(opts, :stop_sequences))
      |> maybe_put("stream", Keyword.get(opts, :stream))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("top_p", Keyword.get(opts, :top_p))

    Pristine.Core.Pipeline.execute(
      Tinkex.Client.manifest(),
      "create_sample_async",
      payload,
      context,
      opts
    )
  end

  @doc """
  Create a streaming sample from a model
  ## Parameters
    * `model` - Required parameter.
    * `prompt` - Required parameter.
    * `opts` - Optional parameters:
      * `:max_tokens` - Optional parameter.
      * `:metadata` - Optional parameter.
      * `:stop_sequences` - Optional parameter.
      * `:stream` - Optional parameter.
      * `:temperature` - Optional parameter.
      * `:top_p` - Optional parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_sample_stream(model, prompt, [])
  """
  @spec create_sample_stream(t(), String.t(), String.t(), keyword()) ::
          {:ok, Tinkex.Types.SampleStreamEvent.t()} | {:error, Pristine.Error.t()}
  def create_sample_stream(%__MODULE__{context: context}, model, prompt, opts \\ []) do
    payload =
      %{
        "model" => model,
        "prompt" => prompt
      }
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> maybe_put("metadata", Keyword.get(opts, :metadata))
      |> maybe_put("stop_sequences", Keyword.get(opts, :stop_sequences))
      |> maybe_put("stream", Keyword.get(opts, :stream))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("top_p", Keyword.get(opts, :top_p))

    Pristine.Core.Pipeline.execute(
      Tinkex.Client.manifest(),
      "create_sample_stream",
      payload,
      context,
      opts
    )
  end

  @doc """
  Create a streaming sample from a model
  ## Parameters
    * `model` - Required parameter.
    * `prompt` - Required parameter.
    * `opts` - Optional parameters:
      * `:max_tokens` - Optional parameter.
      * `:metadata` - Optional parameter.
      * `:stop_sequences` - Optional parameter.
      * `:stream` - Optional parameter.
      * `:temperature` - Optional parameter.
      * `:top_p` - Optional parameter.
  ## Returns
    * `{:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_sample_stream_stream(model, prompt, [])
  """
  @spec create_sample_stream_stream(t(), String.t(), String.t(), keyword()) ::
          {:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}
  def create_sample_stream_stream(%__MODULE__{context: context}, model, prompt, opts \\ []) do
    payload =
      %{
        "model" => model,
        "prompt" => prompt
      }
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> maybe_put("metadata", Keyword.get(opts, :metadata))
      |> maybe_put("stop_sequences", Keyword.get(opts, :stop_sequences))
      |> maybe_put("stream", Keyword.get(opts, :stream))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("top_p", Keyword.get(opts, :top_p))

    Pristine.Core.Pipeline.execute_stream(
      Tinkex.Client.manifest(),
      "create_sample_stream",
      payload,
      context,
      opts
    )
  end

  @doc """
  Get a sample result by ID
  ## Parameters
    * `sample_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_sample(sample_id, [])
  """
  @spec get_sample(t(), term(), keyword()) ::
          {:ok, Tinkex.Types.SampleResult.t()} | {:error, Pristine.Error.t()}
  def get_sample(%__MODULE__{context: context}, sample_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "sample_id" => sample_id
    }

    opts = merge_path_params(opts, path_params)
    Pristine.Core.Pipeline.execute(Tinkex.Client.manifest(), "get_sample", payload, context, opts)
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp merge_path_params(opts, path_params) do
    existing = Keyword.get(opts, :path_params, %{})
    Keyword.put(opts, :path_params, Map.merge(existing, path_params))
  end

  defp encode_ref(nil, _module), do: nil

  defp encode_ref(value, module) do
    if function_exported?(module, :encode, 1) do
      module.encode(value)
    else
      value
    end
  end

  defp encode_ref_list(nil, _module), do: nil

  defp encode_ref_list(values, module) when is_list(values) do
    Enum.map(values, &encode_ref(&1, module))
  end
end
