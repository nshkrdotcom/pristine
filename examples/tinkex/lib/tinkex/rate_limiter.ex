defmodule Tinkex.RateLimiter do
  @moduledoc """
  Shared backoff state per `{base_url, api_key}` combination.

  Uses ETS tables and atomics to implement rate limiting with backoff windows
  that are shared across processes for the same API endpoint and key combination.
  This allows coordinated rate limiting across concurrent requests to the same API.

  ## Usage

      # Get or create a limiter for an endpoint
      limiter = RateLimiter.for_key({"https://api.example.com", "my-api-key"})

      # Check if we should back off
      if RateLimiter.should_backoff?(limiter) do
        RateLimiter.wait_for_backoff(limiter)
      end

      # Set a backoff window (e.g., from server response)
      RateLimiter.set_backoff(limiter, 5000)  # 5 seconds

      # Clear backoff when done
      RateLimiter.clear_backoff(limiter)

  ## ETS Table

  The module uses the `:tinkex_rate_limiters` ETS table which must be created
  before use. This is typically done by the application supervisor.
  """

  alias Tinkex.PoolKey

  @type limiter :: :atomics.atomics_ref()

  @doc """
  Get or create the limiter for a `{base_url, api_key}` tuple.

  The base URL is normalized using `PoolKey.normalize_base_url/1` to ensure
  that equivalent URLs share the same limiter.

  ## Examples

      limiter = RateLimiter.for_key({"https://api.example.com", "my-key"})

  """
  @spec for_key({String.t(), String.t() | nil}) :: limiter()
  def for_key({base_url, api_key}) do
    normalized_base = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized_base, api_key}}

    limiter = :atomics.new(1, signed: true)

    case :ets.insert_new(:tinkex_rate_limiters, {key, limiter}) do
      true ->
        limiter

      false ->
        case :ets.lookup(:tinkex_rate_limiters, key) do
          [{^key, existing}] ->
            existing

          [] ->
            :ets.insert(:tinkex_rate_limiters, {key, limiter})
            limiter
        end
    end
  end

  @doc """
  Determine whether the limiter is currently in a backoff window.

  Returns `true` if the backoff window has not yet expired, `false` otherwise.

  ## Examples

      if RateLimiter.should_backoff?(limiter) do
        # Wait or skip the request
      end

  """
  @spec should_backoff?(limiter()) :: boolean()
  def should_backoff?(limiter) do
    backoff_until = :atomics.get(limiter, 1)

    backoff_until != 0 and System.monotonic_time(:millisecond) < backoff_until
  end

  @doc """
  Set a backoff window in milliseconds.

  The backoff will expire after `duration_ms` milliseconds from now.

  ## Examples

      RateLimiter.set_backoff(limiter, 5000)  # 5 second backoff

  """
  @spec set_backoff(limiter(), non_neg_integer()) :: :ok
  def set_backoff(limiter, duration_ms) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    :atomics.put(limiter, 1, backoff_until)
    :ok
  end

  @doc """
  Clear any active backoff window.

  This immediately allows requests to proceed without waiting.

  ## Examples

      RateLimiter.clear_backoff(limiter)

  """
  @spec clear_backoff(limiter()) :: :ok
  def clear_backoff(limiter) do
    :atomics.put(limiter, 1, 0)
    :ok
  end

  @doc """
  Block until the backoff window has passed.

  If no backoff is active, returns immediately. Otherwise, sleeps until
  the backoff window expires.

  ## Examples

      # Wait for any active backoff before making a request
      RateLimiter.wait_for_backoff(limiter)
      make_request()

  """
  @spec wait_for_backoff(limiter()) :: :ok
  def wait_for_backoff(limiter) do
    backoff_until = :atomics.get(limiter, 1)

    if backoff_until != 0 do
      now = System.monotonic_time(:millisecond)

      wait_ms = backoff_until - now

      if wait_ms > 0 do
        Process.sleep(wait_ms)
      end
    end

    :ok
  end
end
