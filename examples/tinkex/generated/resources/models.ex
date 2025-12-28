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
  """
  @spec get_model(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_model(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "get_model", payload, opts)
  end

  @doc """
  List all available models
  """
  @spec list_models(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_models(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "list_models", payload, opts)
  end
end
