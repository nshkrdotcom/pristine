defmodule Pristine.RuntimeGateway do
  @moduledoc """
  HTTP-family execution boundary for explicit local or Runtime Client placement.

  The gateway is deliberately not selected from application configuration.
  Callers choose a concrete implementation once for an operation and pass all
  placement material explicitly. This keeps local execution distinct from a
  Runtime Client-admitted effect.
  """

  alias ExecutionPlane.{ActiveExecution, ExecutionRef, ExecutionResult}
  alias ExecutionPlane.Family.HTTPRequest
  alias ExecutionPlane.Runtime.Status

  @callback unary(HTTPRequest.t(), keyword()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}
  @callback stream(HTTPRequest.t(), pid(), keyword()) ::
              {:ok, ActiveExecution.t()} | {:error, term()}
  @callback demand(ExecutionRef.t(), pos_integer(), keyword()) ::
              :ok | {:error, term()}
  @callback status(ExecutionRef.t(), keyword()) ::
              {:ok, Status.t()} | {:error, term()}
  @callback cancel(ExecutionRef.t(), keyword()) :: :ok | {:error, term()}

  @doc "The direct, same-node HTTP-family implementation."
  @spec local() :: module()
  def local, do: Pristine.RuntimeGateway.Local

  @doc """
  The admitted Runtime Client implementation.

  Its presence is not a capability advertisement. A caller must inject a
  configured Runtime Client and complete admission material for every effect.
  """
  @spec runtime_client() :: module()
  def runtime_client, do: Pristine.RuntimeGateway.RuntimeClient
end
