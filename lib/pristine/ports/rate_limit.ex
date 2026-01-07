defmodule Pristine.Ports.RateLimit do
  @moduledoc """
  Rate limit boundary.
  """

  @callback within_limit((-> term()), keyword()) :: term()

  @doc """
  Resolve a limiter for a key.
  """
  @callback for_key(term(), keyword()) :: term()

  @doc """
  Block until the limiter allows the operation.
  """
  @callback wait(term(), keyword()) :: :ok

  @doc """
  Clear any stored limiter state.
  """
  @callback clear(term()) :: :ok

  @doc """
  Set a limiter backoff window in milliseconds.
  """
  @callback set(term(), non_neg_integer(), keyword()) :: :ok

  @optional_callbacks [for_key: 2, wait: 2, clear: 1, set: 3]
end
