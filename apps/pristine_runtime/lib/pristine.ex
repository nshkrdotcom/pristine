defmodule Pristine do
  @moduledoc """
  Shared runtime substrate for first-party OpenAPI-based SDKs.
  """

  alias Pristine.Core.Context, as: RuntimeContext
  alias Pristine.Core.Pipeline
  alias Pristine.SDK.Context
  alias Pristine.SDK.OpenAPI.Client, as: OpenAPIClient
  alias Pristine.SDK.Profiles.Foundation, as: FoundationProfile

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
end
