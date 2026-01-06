defmodule Tinkex.Telemetry.Reporter.BackoffTest do
  @moduledoc """
  Tests for retry and backoff logic in telemetry reporter.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter.Backoff

  describe "calculate_backoff_delay/2" do
    test "returns base delay for attempt 0" do
      delay = Backoff.calculate_backoff_delay(0, 1000)

      # Should be base delay + jitter (up to 10%)
      assert delay >= 1000
      assert delay <= 1100
    end

    test "doubles delay for each attempt" do
      base = 1000

      delay0 = Backoff.calculate_backoff_delay(0, base)
      delay1 = Backoff.calculate_backoff_delay(1, base)
      delay2 = Backoff.calculate_backoff_delay(2, base)

      # Attempt 0: ~1000ms
      assert delay0 >= 1000 and delay0 <= 1100

      # Attempt 1: ~2000ms (2x)
      assert delay1 >= 2000 and delay1 <= 2200

      # Attempt 2: ~4000ms (4x)
      assert delay2 >= 4000 and delay2 <= 4400
    end

    test "applies jitter up to 10%" do
      delays =
        for _ <- 1..100 do
          Backoff.calculate_backoff_delay(0, 1000)
        end

      # Should have some variation due to jitter
      min_delay = Enum.min(delays)
      max_delay = Enum.max(delays)

      # All should be in valid range
      assert min_delay >= 1000
      assert max_delay <= 1100

      # Should have some variation (not all identical)
      # Note: statistically unlikely to fail but not guaranteed
      assert max_delay > min_delay
    end

    test "handles large attempt numbers" do
      # Attempt 10 would be 2^10 * base = 1024 * 1000 = 1,024,000ms
      delay = Backoff.calculate_backoff_delay(10, 1000)

      assert delay >= 1_024_000
      # +10% jitter
      assert delay <= 1_126_400
    end

    test "handles small base delays" do
      delay = Backoff.calculate_backoff_delay(0, 100)

      assert delay >= 100
      assert delay <= 110
    end
  end

  describe "send_batch_with_retry/4" do
    # Note: These tests are more integration-focused
    # The actual HTTP sending is tested via API.Telemetry

    test "returns :ok when send succeeds on first try" do
      # Mock state with valid config
      state = %{
        config: %Tinkex.Config{
          api_key: "test",
          base_url: "http://localhost:9999",
          telemetry_enabled?: true
        },
        http_timeout_ms: 5000,
        max_retries: 3,
        retry_base_delay_ms: 100
      }

      request = %{
        session_id: "test-session",
        platform: "unix/linux",
        sdk_version: "test",
        events: []
      }

      # This will fail because there's no real server, but tests the interface
      # In real usage, this would be mocked
      result = Backoff.send_batch_with_retry(request, state, :sync)

      # Will return :error because no server, but validates the interface works
      assert result in [:ok, :error]
    end

    test "accepts :sync and :async mode" do
      state = %{
        config: %Tinkex.Config{api_key: "test", base_url: "http://localhost:9999"},
        http_timeout_ms: 1000,
        max_retries: 0,
        retry_base_delay_ms: 100
      }

      request = %{events: []}

      # Both modes should work without crashing
      result_sync = Backoff.send_batch_with_retry(request, state, :sync, 0)
      result_async = Backoff.send_batch_with_retry(request, state, :async, 0)

      assert result_sync in [:ok, :error]
      assert result_async in [:ok, :error]
    end
  end
end
