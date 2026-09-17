defmodule Pristine.Adapters.RateLimit.BackoffWindow do
  @moduledoc """
  Rate limit adapter backed by Foundation.RateLimit.BackoffWindow.
  """

  @behaviour Pristine.Ports.RateLimit

  alias Foundation.RateLimit.BackoffWindow

  @impl true
  def within_limit(fun, opts) when is_function(fun, 0) do
    key = Keyword.get(opts, :key, :default)
    registry = resolve_registry(opts)
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
    registry = resolve_registry(opts)
    limiter = BackoffWindow.for_key(registry, key)
    BackoffWindow.set(limiter, duration_ms, opts)
  end

  @impl true
  def for_key(key, opts \\ []) do
    registry = resolve_registry(opts)
    BackoffWindow.for_key(registry, key)
  end

  @impl true
  def wait(limiter, opts \\ []) do
    BackoffWindow.wait(limiter, opts)
  end

  @impl true
  def clear(limiter) do
    BackoffWindow.clear(limiter)
  end

  @impl true
  def set(limiter, duration_ms, opts \\ []) do
    BackoffWindow.set(limiter, duration_ms, opts)
  end

  defp resolve_registry(opts) do
    # Foundation owns default-registry creation and lifetime. Explicit tables
    # need not have an heir: their creating process owns their lifetime.
    Keyword.get(opts, :registry) || BackoffWindow.default_registry()
  end
end
