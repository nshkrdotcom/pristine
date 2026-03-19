defmodule Pristine do
  @moduledoc """
  Public runtime entrypoint for `Pristine.Client` and `Pristine.Operation`.
  """

  alias Pristine.Client
  alias Pristine.Core.Pipeline
  alias Pristine.Operation

  @doc """
  Execute a rendered runtime operation against a runtime client.
  """
  @spec execute(Client.t(), Operation.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(%Client{} = client, %Operation{} = operation, opts \\ []) do
    Pipeline.execute_operation(operation, client.context, opts)
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
