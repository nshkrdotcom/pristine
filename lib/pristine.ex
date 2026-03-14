defmodule Pristine do
  @moduledoc """
  Manifest-driven hexagonal core for SDK generation.
  """

  alias Pristine.Core.Context, as: RuntimeContext
  alias Pristine.Core.Pipeline
  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint
  alias Pristine.Runtime
  alias Pristine.SDK.Context
  alias Pristine.SDK.OpenAPI.Client, as: OpenAPIClient
  alias Pristine.SDK.Profiles.Foundation, as: FoundationProfile

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
    RuntimeContext.new(opts)
  end

  @doc """
  Build a Foundation-backed production context.
  """
  @spec foundation_context(keyword()) :: Context.t()
  def foundation_context(opts \\ []) do
    FoundationProfile.context(opts)
  end

  @doc """
  Execute an endpoint by id with the provided payload.
  """
  @spec execute(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(manifest, endpoint_id, payload, %RuntimeContext{} = context, opts \\ []) do
    Runtime.execute(manifest, endpoint_id, payload, context, opts)
  end

  @doc """
  Execute a generic request spec without rebuilding a manifest.

  `Pristine.execute_request/3` is the public low-level escape hatch for both:

  - simple ad hoc request specs
  - OpenAPI-generated request maps emitted by Pristine-generated SDKs

  Request paths and path params still go through the same traversal validation
  used by manifest-defined endpoints.
  """
  @spec execute_request(
          OpenAPIClient.request_spec_t() | OpenAPIClient.request_t(),
          Pristine.SDK.Context.t(),
          keyword()
        ) ::
          {:ok, term()} | {:error, term()}
  def execute_request(request_spec, %RuntimeContext{} = context, opts \\ []) do
    Pipeline.execute_request(request_spec, context, opts)
  end

  @doc """
  Execute a direct endpoint definition without reconstructing a manifest.
  """
  @spec execute_endpoint(Endpoint.t(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_endpoint(%Endpoint{} = endpoint, payload, %RuntimeContext{} = context, opts \\ []) do
    Runtime.execute_endpoint(endpoint, payload, context, opts)
  end
end
