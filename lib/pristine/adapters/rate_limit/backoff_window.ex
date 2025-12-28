defmodule Pristine.Adapters.RateLimit.BackoffWindow do
  @moduledoc """
  Rate limit adapter backed by Foundation.RateLimit.BackoffWindow.
  """

  @behaviour Pristine.Ports.RateLimit

  alias Foundation.RateLimit.BackoffWindow

  @impl true
  def within_limit(fun, opts) when is_function(fun, 0) do
    key = Keyword.get(opts, :key, :default)
    registry = Keyword.get(opts, :registry, BackoffWindow.default_registry())
    limiter = BackoffWindow.for_key(registry, key)

    if BackoffWindow.should_backoff?(limiter, opts) do
      BackoffWindow.wait(limiter, opts)
    end

    fun.()
  end

  @doc """
  Set a backoff window for a key.
  """
  @spec backoff(term(), non_neg_integer(), keyword()) :: :ok
  def backoff(key, duration_ms, opts \\ []) do
    registry = Keyword.get(opts, :registry, BackoffWindow.default_registry())
    limiter = BackoffWindow.for_key(registry, key)
    BackoffWindow.set(limiter, duration_ms, opts)
  end
end
