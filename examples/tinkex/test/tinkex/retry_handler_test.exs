defmodule Tinkex.RetryHandlerTest do
  use ExUnit.Case, async: true

  alias Tinkex.RetryHandler
  alias Tinkex.Error

  describe "new/1" do
    test "creates handler with defaults" do
      handler = RetryHandler.new()

      assert handler.max_retries == :infinity
      assert handler.base_delay_ms == 500
      assert handler.max_delay_ms == 10_000
      assert handler.jitter_pct == 0.25
      assert handler.attempt == 0
      assert is_integer(handler.start_time)
    end

    test "accepts custom options" do
      handler =
        RetryHandler.new(
          max_retries: 5,
          base_delay_ms: 100,
          max_delay_ms: 5_000,
          jitter_pct: 0.1
        )

      assert handler.max_retries == 5
      assert handler.base_delay_ms == 100
      assert handler.max_delay_ms == 5_000
      assert handler.jitter_pct == 0.1
    end
  end

  describe "retry?/2" do
    test "returns false when max retries reached" do
      handler = RetryHandler.new(max_retries: 3)
      handler = %{handler | attempt: 3}

      refute RetryHandler.retry?(handler, %Error{})
    end

    test "returns true when under max retries" do
      handler = RetryHandler.new(max_retries: 3)
      handler = %{handler | attempt: 2}

      assert RetryHandler.retry?(handler, %Error{type: :server_error})
    end

    test "returns true with :infinity max_retries" do
      handler = RetryHandler.new(max_retries: :infinity)
      handler = %{handler | attempt: 1000}

      assert RetryHandler.retry?(handler, %Error{type: :server_error})
    end

    test "checks Error.retryable? for Error structs" do
      handler = RetryHandler.new(max_retries: 10)

      # Server errors are retryable
      server_error = Error.new(:server_error, "Internal error", status: 500)
      assert RetryHandler.retry?(handler, server_error)

      # User errors are not retryable
      user_error = Error.new(:bad_request, "Invalid input", status: 400, category: :user)
      refute RetryHandler.retry?(handler, user_error)
    end

    test "returns true for non-Error terms" do
      handler = RetryHandler.new(max_retries: 10)

      assert RetryHandler.retry?(handler, :some_error)
      assert RetryHandler.retry?(handler, "string error")
      assert RetryHandler.retry?(handler, {:error, :timeout})
    end
  end

  describe "next_delay/1" do
    test "calculates exponential backoff" do
      handler = RetryHandler.new(base_delay_ms: 100, max_delay_ms: 10_000, jitter_pct: 0)

      # attempt 0: 100 * 2^0 = 100
      assert RetryHandler.next_delay(handler) == 100

      # attempt 1: 100 * 2^1 = 200
      handler = %{handler | attempt: 1}
      assert RetryHandler.next_delay(handler) == 200

      # attempt 2: 100 * 2^2 = 400
      handler = %{handler | attempt: 2}
      assert RetryHandler.next_delay(handler) == 400
    end

    test "caps delay at max_delay_ms" do
      handler = RetryHandler.new(base_delay_ms: 1000, max_delay_ms: 5_000, jitter_pct: 0)

      # attempt 3: 1000 * 2^3 = 8000, but capped at 5000
      handler = %{handler | attempt: 3}
      assert RetryHandler.next_delay(handler) == 5_000
    end

    test "applies jitter within bounds" do
      handler = RetryHandler.new(base_delay_ms: 1000, max_delay_ms: 10_000, jitter_pct: 0.25)

      # Run multiple times to verify jitter is applied
      delays = for _ <- 1..100, do: RetryHandler.next_delay(handler)

      # All delays should be within jitter range: 750-1250 for 1000 base
      assert Enum.all?(delays, fn d -> d >= 0 and d <= 10_000 end)

      # Should have some variation
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1
    end
  end

  describe "increment_attempt/1" do
    test "increments the attempt counter" do
      handler = RetryHandler.new()
      assert handler.attempt == 0

      handler = RetryHandler.increment_attempt(handler)
      assert handler.attempt == 1

      handler = RetryHandler.increment_attempt(handler)
      assert handler.attempt == 2
    end
  end

  describe "record_progress/1" do
    test "updates last_progress_at" do
      handler = RetryHandler.new()
      original = handler.last_progress_at

      Process.sleep(5)
      handler = RetryHandler.record_progress(handler)

      assert handler.last_progress_at > original
    end
  end

  describe "progress_timeout?/1" do
    test "returns false on first attempt" do
      handler = RetryHandler.new(progress_timeout_ms: 100)
      refute RetryHandler.progress_timeout?(handler)
    end

    test "returns false when within timeout" do
      handler = RetryHandler.new(progress_timeout_ms: 1000)
      handler = %{handler | attempt: 1}

      refute RetryHandler.progress_timeout?(handler)
    end

    test "returns true when timeout exceeded" do
      handler = RetryHandler.new(progress_timeout_ms: 10)

      handler = %{
        handler
        | attempt: 1,
          last_progress_at: System.monotonic_time(:millisecond) - 50
      }

      assert RetryHandler.progress_timeout?(handler)
    end
  end

  describe "elapsed_ms/1" do
    test "returns elapsed time since start" do
      handler = RetryHandler.new()
      Process.sleep(10)

      elapsed = RetryHandler.elapsed_ms(handler)
      assert elapsed >= 10
    end
  end
end
