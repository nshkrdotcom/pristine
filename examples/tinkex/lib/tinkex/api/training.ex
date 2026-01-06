defmodule Tinkex.API.Training do
  @moduledoc """
  Training API endpoints.

  Uses :training pool (sequential, long-running operations).
  Pool size: 5 connections.

  Note: The convenience functions (forward_backward/2, optim_step/2, forward/2)
  that automatically await futures require the Future module which is not yet
  implemented. Use the *_future variants for now.
  """

  @doc """
  Forward-backward pass for gradient computation.

  Returns a server-side future reference that must be polled.
  """
  @spec forward_backward_future(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_backward_future(request, opts) do
    client = Tinkex.API.client_module(opts)

    opts =
      opts
      |> Keyword.put(:pool_type, :training)
      |> Keyword.put_new(:transform, drop_nil?: true)

    client.post("/api/v1/forward_backward", request, opts)
  end

  @doc """
  Optimizer step to update model parameters.

  Returns a server-side future reference that must be polled.
  """
  @spec optim_step_future(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def optim_step_future(request, opts) do
    client = Tinkex.API.client_module(opts)

    opts =
      opts
      |> Keyword.put(:pool_type, :training)
      |> Keyword.put_new(:transform, drop_nil?: true)

    client.post("/api/v1/optim_step", request, opts)
  end

  @doc """
  Forward pass only (inference).

  Returns a server-side future reference that must be polled.
  """
  @spec forward_future(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_future(request, opts) do
    client = Tinkex.API.client_module(opts)

    opts =
      opts
      |> Keyword.put(:pool_type, :training)
      |> Keyword.put_new(:transform, drop_nil?: true)

    client.post("/api/v1/forward", request, opts)
  end
end
