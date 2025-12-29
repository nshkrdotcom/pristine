defmodule Tinkex.Models do
  @moduledoc """
  Models resource endpoints.

  This module provides functions for interacting with models resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(%{context: Pristine.Core.Context.t()}) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  Get details for a specific model
  ## Parameters
    * `model_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_model(model_id, [])
  """
  @spec get_model(t(), term(), keyword()) ::
          {:ok, Tinkex.Types.Model.t()} | {:error, Pristine.Error.t()}
  def get_model(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "model_id" => model_id
    }

    opts = merge_path_params(opts, path_params)
    Pristine.Core.Pipeline.execute(Tinkex.Client.manifest(), "get_model", payload, context, opts)
  end

  @doc """
  List all available models
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.list_models()
  """
  @spec list_models(t(), keyword()) ::
          {:ok, Tinkex.Types.ModelList.t()} | {:error, Pristine.Error.t()}
  def list_models(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Core.Pipeline.execute(
      Tinkex.Client.manifest(),
      "list_models",
      payload,
      context,
      opts
    )
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
