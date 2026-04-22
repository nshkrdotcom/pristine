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
    with :ok <- reject_public_simulation_selector(opts) do
      Pipeline.execute_operation(operation, client.context, opts)
    end
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
    with :ok <- reject_public_simulation_selector(request_spec),
         :ok <- reject_public_simulation_selector(opts) do
      Pipeline.execute_request(request_spec, context, opts)
    end
  end

  @doc """
  Open a streaming request for a rendered runtime operation.
  """
  @spec stream(Client.t(), Operation.t(), keyword()) ::
          {:ok, Pristine.Response.t()} | {:error, term()}
  def stream(%Client{} = client, %Operation{} = operation, opts \\ []) do
    with :ok <- reject_public_simulation_selector(opts) do
      Pipeline.stream_operation(operation, client.context, opts)
    end
  end

  defp reject_public_simulation_selector(values) when is_list(values) do
    if Enum.any?(values, &public_simulation_entry?/1) do
      {:error, {:public_simulation_selector_forbidden, :pristine}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(values) when is_map(values) do
    if Map.has_key?(values, :simulation) or Map.has_key?(values, "simulation") do
      {:error, {:public_simulation_selector_forbidden, :pristine}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(_values), do: :ok

  defp public_simulation_entry?({key, _value}), do: key in [:simulation, "simulation"]
  defp public_simulation_entry?(_entry), do: false
end
