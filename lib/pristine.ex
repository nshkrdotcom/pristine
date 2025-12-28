defmodule Pristine do
  @moduledoc """
  Manifest-driven hexagonal core for SDK generation.
  """

  alias Pristine.Core.Context
  alias Pristine.Manifest
  alias Pristine.Runtime

  @doc """
  Normalize and validate a manifest.
  """
  @spec load_manifest(map()) :: {:ok, Manifest.t()} | {:error, [String.t()]}
  def load_manifest(manifest) when is_map(manifest) do
    Manifest.load(manifest)
  end

  @doc """
  Load a manifest from disk.
  """
  @spec load_manifest_file(Path.t()) :: {:ok, Manifest.t()} | {:error, [String.t()]}
  def load_manifest_file(path) do
    Manifest.load_file(path)
  end

  @doc """
  Build an execution context.
  """
  @spec context(keyword()) :: Context.t()
  def context(opts \\ []) do
    Context.new(opts)
  end

  @doc """
  Execute an endpoint by id with the provided payload.
  """
  @spec execute(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(manifest, endpoint_id, payload, %Context{} = context, opts \\ []) do
    Runtime.execute(manifest, endpoint_id, payload, context, opts)
  end
end
