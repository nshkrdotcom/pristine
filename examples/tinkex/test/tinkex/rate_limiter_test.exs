defmodule Tinkex.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Tinkex.RateLimiter

  setup do
    # Ensure ETS table exists
    if :ets.whereis(:tinkex_rate_limiters) == :undefined do
      :ets.new(:tinkex_rate_limiters, [:set, :public, :named_table])
    end

    :ok
  end

  describe "for_key/1" do
    test "returns atomics reference" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      assert is_reference(limiter)
    end

    test "reuses atomics for normalized URLs" do
      base_url = "https://EXAMPLE.com:443"
      api_key = "key-#{:erlang.unique_integer([:positive])}"

      limiter1 = RateLimiter.for_key({base_url, api_key})
      limiter2 = RateLimiter.for_key({"https://example.com", api_key})

      assert limiter1 == limiter2
    end

    test "creates different limiters for different api keys" do
      base_url = unique_base_url()

      limiter1 = RateLimiter.for_key({base_url, "key-1"})
      limiter2 = RateLimiter.for_key({base_url, "key-2"})

      assert limiter1 != limiter2
    end

    test "insert_new prevents duplicate limiter creation" do
      {base_url, api_key} = unique_key()

      task =
        Task.async(fn ->
          RateLimiter.for_key({base_url, api_key})
        end)

      limiter1 = RateLimiter.for_key({base_url, api_key})
      limiter2 = Task.await(task, 2_000)

      assert limiter1 == limiter2
    end
  end

  describe "should_backoff?/1" do
    test "returns false when no backoff set" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      refute RateLimiter.should_backoff?(limiter)
    end

    test "returns true when in backoff window" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      RateLimiter.set_backoff(limiter, 1000)

      assert RateLimiter.should_backoff?(limiter)
    end

    test "returns false after backoff expires" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      RateLimiter.set_backoff(limiter, 10)
      Process.sleep(20)

      refute RateLimiter.should_backoff?(limiter)
    end
  end

  describe "set_backoff/2" do
    test "activates backoff window" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      assert :ok = RateLimiter.set_backoff(limiter, 100)
      assert RateLimiter.should_backoff?(limiter)
    end
  end

  describe "clear_backoff/1" do
    test "clears active backoff" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      RateLimiter.set_backoff(limiter, 1000)
      assert RateLimiter.should_backoff?(limiter)

      assert :ok = RateLimiter.clear_backoff(limiter)
      refute RateLimiter.should_backoff?(limiter)
    end
  end

  describe "wait_for_backoff/1" do
    test "returns immediately when no backoff" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      start_ms = System.monotonic_time(:millisecond)
      assert :ok = RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start_ms

      assert elapsed < 50
    end

    test "waits for backoff to expire" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      RateLimiter.set_backoff(limiter, 100)

      start_ms = System.monotonic_time(:millisecond)
      assert :ok = RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start_ms

      assert elapsed >= 80
    end

    test "cooperates with should_backoff?" do
      {base_url, api_key} = unique_key()
      limiter = RateLimiter.for_key({base_url, api_key})

      RateLimiter.clear_backoff(limiter)
      refute RateLimiter.should_backoff?(limiter)

      RateLimiter.set_backoff(limiter, 120)
      assert RateLimiter.should_backoff?(limiter)

      start_ms = System.monotonic_time(:millisecond)
      :ok = RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start_ms
      assert elapsed >= 100

      RateLimiter.clear_backoff(limiter)
      refute RateLimiter.should_backoff?(limiter)
    end
  end

  defp unique_key do
    {unique_base_url(), "key-#{:erlang.unique_integer([:positive])}"}
  end

  defp unique_base_url do
    "https://example#{:erlang.unique_integer([:positive])}.com"
  end
end
