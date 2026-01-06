defmodule Tinkex.RetryTest do
  use ExUnit.Case, async: true

  alias Tinkex.Retry
  alias Tinkex.RetryHandler
  alias Tinkex.Error

  describe "with_retry/2" do
    test "returns successful result without retrying" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 1
    end

    test "retries on error and succeeds" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.add(call_count, 1, 1)
            current = :counters.get(call_count, 1)

            if current < 3 do
              {:error, Error.new(:server_error, "temporary failure")}
            else
              {:ok, "success after retries"}
            end
          end,
          handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0)
        )

      assert result == {:ok, "success after retries"}
      assert :counters.get(call_count, 1) == 3
    end

    test "returns error after max retries" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.new(:server_error, "persistent failure")}
          end,
          handler: RetryHandler.new(max_retries: 3, base_delay_ms: 1, jitter_pct: 0)
        )

      assert {:error, %Error{}} = result
      # Initial attempt + 3 retries = 4 total calls
      assert :counters.get(call_count, 1) == 4
    end

    test "does not retry non-retryable errors" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.new(:bad_request, "invalid input", status: 400, category: :user)}
          end,
          handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1)
        )

      assert {:error, %Error{type: :bad_request}} = result
      # Only one call - no retries for user errors
      assert :counters.get(call_count, 1) == 1
    end

    test "handles exceptions with retry" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.add(call_count, 1, 1)
            current = :counters.get(call_count, 1)

            if current < 2 do
              raise "temporary exception"
            else
              {:ok, "recovered"}
            end
          end,
          handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0)
        )

      assert result == {:ok, "recovered"}
      assert :counters.get(call_count, 1) == 2
    end

    test "returns error after exception max retries" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            raise "persistent exception"
          end,
          handler: RetryHandler.new(max_retries: 2, base_delay_ms: 1, jitter_pct: 0)
        )

      assert {:error, %Error{type: :request_failed}} = result
      assert :counters.get(call_count, 1) == 3
    end

    test "uses default handler when not provided" do
      result = Retry.with_retry(fn -> {:ok, "default handler"} end)
      assert result == {:ok, "default handler"}
    end

    test "emits telemetry events" do
      parent = self()

      :telemetry.attach_many(
        "test-retry-telemetry",
        [
          [:tinkex, :retry, :attempt, :start],
          [:tinkex, :retry, :attempt, :stop],
          [:tinkex, :retry, :attempt, :retry],
          [:tinkex, :retry, :attempt, :failed]
        ],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      call_count = :counters.new(1, [:atomics])

      Retry.with_retry(
        fn ->
          count = :counters.add(call_count, 1, 1)
          current = :counters.get(call_count, 1)

          if current < 2 do
            {:error, Error.new(:server_error, "retry me")}
          else
            {:ok, "success"}
          end
        end,
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0),
        telemetry_metadata: %{operation: "test"}
      )

      # Should receive start, retry (for first failure), start (second attempt), stop (success)
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :start], _, %{attempt: 0}}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :retry], _, _}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :start], _, %{attempt: 1}}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :stop], _, %{result: :ok}}

      :telemetry.detach("test-retry-telemetry")
    end
  end
end
