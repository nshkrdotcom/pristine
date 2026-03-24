defmodule Pristine do
  @moduledoc """
  Shared runtime substrate for first-party OpenAPI-based SDKs.
  """

  alias Pristine.Client
  alias Pristine.Core.Context, as: RuntimeContext
  alias Pristine.Core.Pipeline
  alias Pristine.Operation
  alias Pristine.Profiles.Foundation
  alias Pristine.SDK.Context
  alias Pristine.SDK.OpenAPI.Client, as: OpenAPIClient

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
    Foundation.context(opts)
  end

  @doc """
  Execute a rendered runtime operation against a runtime client.
  """
  @spec execute(Client.t(), Operation.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(%Client{} = client, %Operation{} = operation, opts \\ []) do
    Pipeline.execute_operation(operation, client.context, opts)
  end

  @doc """
  Execute a generic request spec without rebuilding a runtime manifest.
  """
  @spec execute_request(
          OpenAPIClient.request_spec_t() | OpenAPIClient.request_t(),
          Context.t(),
          keyword()
        ) ::
          {:ok, term()} | {:error, term()}
  def execute_request(request_spec, %RuntimeContext{} = context, opts \\ []) do
    Pipeline.execute_request(request_spec, context, opts)
  end

  @doc """
  Open a streaming request for a rendered runtime operation.
  """
  @spec stream(Client.t(), Operation.t(), keyword()) ::
          {:ok, Pristine.Response.t()} | {:error, term()}
  def stream(%Client{} = client, %Operation{} = operation, opts \\ []) do
    Pipeline.stream_operation(operation, client.context, opts)
  end
end
