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
  """
  @spec create_sample(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_sample(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "create_sample", payload, opts)
  end

  @doc """
  Create a sample asynchronously, returns a future
  """
  @spec create_sample_async(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_sample_async(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "create_sample_async", payload, opts)
  end

  @doc """
  Create a streaming sample from a model
  """
  @spec create_sample_stream(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_sample_stream(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "create_sample_stream", payload, opts)
  end

  @doc """
  Get a sample result by ID
  """
  @spec get_sample(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_sample(%__MODULE__{context: context}, payload, opts \\ []) do
    Pristine.Runtime.execute(context, "get_sample", payload, opts)
  end
end
