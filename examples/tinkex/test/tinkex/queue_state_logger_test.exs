defmodule Tinkex.QueueStateLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tinkex.QueueStateLogger

  describe "log_state_change/4" do
    test "does not log for :active state" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:active, :sampling, "session-123")
        end)

      assert log == ""
    end

    test "logs warning for paused_rate_limit sampling" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_rate_limit, :sampling, "session-123")
        end)

      assert log =~ "[warning]"
      assert log =~ "Sampling is paused for session-123"
      assert log =~ "concurrent sampler weights limit hit"
    end

    test "logs warning for paused_rate_limit training" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_rate_limit, :training, "model-456")
        end)

      assert log =~ "[warning]"
      assert log =~ "Training is paused for model-456"
      assert log =~ "concurrent training clients rate limit hit"
    end

    test "logs warning for paused_capacity" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_capacity, :sampling, "session-789")
        end)

      assert log =~ "[warning]"
      assert log =~ "Sampling is paused for session-789"
      assert log =~ "Tinker backend is running short on capacity"
    end

    test "uses server reason when provided" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(
            :paused_rate_limit,
            :sampling,
            "sess-1",
            "custom reason"
          )
        end)

      assert log =~ "custom reason"
      refute log =~ "concurrent sampler weights limit hit"
    end
  end

  describe "resolve_reason/3" do
    test "prefers non-empty server reason" do
      assert QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, "server says no") ==
               "server says no"
    end

    test "uses default for nil server reason" do
      assert QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, nil) ==
               "concurrent sampler weights limit hit"
    end

    test "uses default for empty server reason" do
      assert QueueStateLogger.resolve_reason(:paused_rate_limit, :training, "") ==
               "concurrent training clients rate limit hit"
    end
  end

  describe "should_log?/2" do
    test "returns true for nil last_logged" do
      assert QueueStateLogger.should_log?(nil) == true
    end

    test "returns true when interval exceeded" do
      old_time = System.monotonic_time(:millisecond) - 61_000
      assert QueueStateLogger.should_log?(old_time) == true
    end

    test "returns false within interval" do
      recent_time = System.monotonic_time(:millisecond) - 30_000
      assert QueueStateLogger.should_log?(recent_time) == false
    end

    test "respects custom interval" do
      old_time = System.monotonic_time(:millisecond) - 5_000
      assert QueueStateLogger.should_log?(old_time, 3_000) == true
      assert QueueStateLogger.should_log?(old_time, 10_000) == false
    end
  end

  describe "reason_for_state/2" do
    test "returns correct reason for sampling rate limit" do
      assert QueueStateLogger.reason_for_state(:paused_rate_limit, :sampling) ==
               "concurrent sampler weights limit hit"
    end

    test "returns correct reason for training rate limit" do
      assert QueueStateLogger.reason_for_state(:paused_rate_limit, :training) ==
               "concurrent training clients rate limit hit"
    end

    test "returns capacity reason for paused_capacity" do
      assert QueueStateLogger.reason_for_state(:paused_capacity, :sampling) ==
               "Tinker backend is running short on capacity, please wait"

      assert QueueStateLogger.reason_for_state(:paused_capacity, :training) ==
               "Tinker backend is running short on capacity, please wait"
    end

    test "returns unknown for other states" do
      assert QueueStateLogger.reason_for_state(:unknown, :sampling) == "unknown"
      assert QueueStateLogger.reason_for_state(:active, :training) == "unknown"
    end
  end

  describe "maybe_log/5" do
    test "returns unchanged timestamp for :active state" do
      old_time = 12345
      result = QueueStateLogger.maybe_log(:active, :sampling, "sess-1", old_time)
      assert result == old_time
    end

    test "logs and returns new timestamp when interval exceeded" do
      old_time = System.monotonic_time(:millisecond) - 61_000

      log =
        capture_log(fn ->
          result = QueueStateLogger.maybe_log(:paused_rate_limit, :sampling, "sess-1", old_time)
          send(self(), {:result, result})
        end)

      assert_receive {:result, result}
      assert log =~ "Sampling is paused"
      assert result > old_time
    end

    test "does not log and returns same timestamp within interval" do
      recent_time = System.monotonic_time(:millisecond) - 30_000

      log =
        capture_log(fn ->
          result =
            QueueStateLogger.maybe_log(:paused_rate_limit, :sampling, "sess-1", recent_time)

          send(self(), {:result, result})
        end)

      assert_receive {:result, result}
      assert log == ""
      assert result == recent_time
    end

    test "logs with server reason when provided" do
      log =
        capture_log(fn ->
          QueueStateLogger.maybe_log(
            :paused_capacity,
            :training,
            "model-1",
            nil,
            "server overloaded"
          )
        end)

      assert log =~ "server overloaded"
    end
  end
end
