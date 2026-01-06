defmodule Tinkex.API.RetryConfigTest do
  @moduledoc """
  Tests for API-level retry configuration with Python SDK parity.
  """
  use ExUnit.Case, async: true

  alias Tinkex.API.RetryConfig

  describe "new/1" do
    test "builds with defaults" do
      config = RetryConfig.new()

      assert config.max_retries == 10
      assert config.initial_delay_ms == 500
      assert config.max_delay_ms == 10_000
    end

    test "accepts keyword overrides" do
      config =
        RetryConfig.new(
          max_retries: 5,
          initial_delay_ms: 1000,
          max_delay_ms: 5000
        )

      assert config.max_retries == 5
      assert config.initial_delay_ms == 1000
      assert config.max_delay_ms == 5000
    end
  end

  describe "retry_delay/1" do
    test "returns delay within jitter range for attempt 0" do
      # Python: 500ms * 2^0 = 500ms, with jitter [0.75, 1.0] = [375, 500]
      delay = RetryConfig.retry_delay(0)
      assert delay >= 375
      assert delay <= 500
    end

    test "returns delay within jitter range for attempt 1" do
      # Python: 500ms * 2^1 = 1000ms, with jitter [0.75, 1.0] = [750, 1000]
      delay = RetryConfig.retry_delay(1)
      assert delay >= 750
      assert delay <= 1000
    end

    test "returns delay within jitter range for attempt 2" do
      # Python: 500ms * 2^2 = 2000ms, with jitter [0.75, 1.0] = [1500, 2000]
      delay = RetryConfig.retry_delay(2)
      assert delay >= 1500
      assert delay <= 2000
    end

    test "caps delay at max_delay" do
      # Python: 500ms * 2^5 = 16000ms, capped at 10000ms, jitter [7500, 10000]
      delay = RetryConfig.retry_delay(5)
      assert delay >= 7500
      assert delay <= 10_000
    end

    test "delay never exceeds max_delay_ms" do
      # Even at high attempt numbers, should stay capped
      for attempt <- 10..15 do
        delay = RetryConfig.retry_delay(attempt)
        assert delay <= 10_000, "Attempt #{attempt} delay #{delay} exceeded max"
      end
    end
  end

  describe "retry_delay/3" do
    test "uses custom initial and max delays" do
      # 100ms * 2^0 = 100ms, jitter [0.75, 1.0] = [75, 100]
      delay = RetryConfig.retry_delay(0, 100, 1000)
      assert delay >= 75
      assert delay <= 100
    end

    test "respects custom max_delay" do
      # 100ms * 2^4 = 1600ms, capped at 500ms, jitter [375, 500]
      delay = RetryConfig.retry_delay(4, 100, 500)
      assert delay >= 375
      assert delay <= 500
    end
  end

  describe "retryable_status?/1" do
    test "408 Request Timeout is retryable" do
      assert RetryConfig.retryable_status?(408)
    end

    test "409 Conflict is retryable" do
      assert RetryConfig.retryable_status?(409)
    end

    test "429 Too Many Requests is retryable" do
      assert RetryConfig.retryable_status?(429)
    end

    test "5xx errors are retryable" do
      assert RetryConfig.retryable_status?(500)
      assert RetryConfig.retryable_status?(502)
      assert RetryConfig.retryable_status?(503)
      assert RetryConfig.retryable_status?(504)
      assert RetryConfig.retryable_status?(599)
    end

    test "4xx errors (except 408, 409, 429) are not retryable" do
      refute RetryConfig.retryable_status?(400)
      refute RetryConfig.retryable_status?(401)
      refute RetryConfig.retryable_status?(403)
      refute RetryConfig.retryable_status?(404)
      refute RetryConfig.retryable_status?(422)
    end

    test "2xx and 3xx are not retryable" do
      refute RetryConfig.retryable_status?(200)
      refute RetryConfig.retryable_status?(201)
      refute RetryConfig.retryable_status?(301)
      refute RetryConfig.retryable_status?(302)
    end

    test "600+ are not retryable" do
      refute RetryConfig.retryable_status?(600)
    end
  end

  describe "Python SDK parity" do
    test "default initial delay matches Python INITIAL_RETRY_DELAY (0.5s)" do
      config = RetryConfig.new()
      assert config.initial_delay_ms == 500
    end

    test "default max delay matches Python MAX_RETRY_DELAY (10s)" do
      config = RetryConfig.new()
      assert config.max_delay_ms == 10_000
    end

    test "exponential backoff formula matches Python" do
      # Python: sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)
      # Then jitter is applied: jitter = 1 - 0.25 * random() (range 0.75-1.0)

      # We test the distribution by sampling multiple times
      samples = for _ <- 1..100, do: RetryConfig.retry_delay(2)
      min_sample = Enum.min(samples)
      max_sample = Enum.max(samples)

      # Base is 500 * 2^2 = 2000, jitter range [0.75, 1.0] = [1500, 2000]
      assert min_sample >= 1500
      assert max_sample <= 2000
    end
  end
end
