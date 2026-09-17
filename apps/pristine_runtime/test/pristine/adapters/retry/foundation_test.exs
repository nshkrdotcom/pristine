defmodule Pristine.Adapters.Retry.FoundationTest do
  use ExUnit.Case, async: true

  alias Foundation.Backoff
  alias Pristine.Adapters.Retry.Foundation, as: RetryAdapter

  test "zero initial delay or cap disables backoff" do
    for opts <- [[base_ms: 0, max_ms: 5_000], [base_ms: 500, max_ms: 0]] do
      backoff = RetryAdapter.build_backoff(opts)

      for attempt <- [0, 1, 2] do
        assert Backoff.delay(backoff, attempt) == 0
      end
    end
  end

  test "total retry budget stops before an over-budget delay and keeps the last result" do
    for budget <- [100, 101] do
      clock = :counters.new(1, [:atomics])
      attempts = :counters.new(1, [:atomics])

      result =
        RetryAdapter.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            :counters.add(clock, 1, 40)
            {:error, :last_failure}
          end,
          max_attempts: 3,
          retry_on: fn _ -> true end,
          retry_budget_ms: budget,
          retry_after_ms_fun: fn _ -> 60 end,
          time_fun: fn :millisecond -> :counters.get(clock, 1) end,
          sleep_fun: fn ms -> :counters.add(clock, 1, ms) end
        )

      assert result == {:error, :last_failure}
      assert :counters.get(attempts, 1) == if(budget == 100, do: 1, else: 2)
      assert :counters.get(clock, 1) == if(budget == 100, do: 40, else: 140)
    end
  end

  test "retries when retry_on returns true and returns original result" do
    attempt = :counters.new(1, [:atomics])

    fun = fn ->
      count = :counters.get(attempt, 1)
      :counters.add(attempt, 1, 1)

      if count < 1 do
        {:ok, :retry_me}
      else
        {:ok, :done}
      end
    end

    retry_on = fn
      {:ok, :retry_me} -> true
      _ -> false
    end

    sleep_fun = fn _ -> :ok end

    assert {:ok, :done} =
             RetryAdapter.with_retry(fun,
               max_attempts: 2,
               retry_on: retry_on,
               sleep_fun: sleep_fun
             )
  end

  test "returns error without retry when retry_on is false" do
    fun = fn -> {:error, :boom} end
    retry_on = fn _ -> false end

    assert {:error, :boom} =
             RetryAdapter.with_retry(fun,
               max_attempts: 2,
               retry_on: retry_on,
               sleep_fun: fn _ -> :ok end
             )
  end

  test "returns last result when retries are exhausted" do
    fun = fn -> {:ok, :retry_me} end

    retry_on = fn
      {:ok, :retry_me} -> true
      _ -> false
    end

    assert {:ok, :retry_me} =
             RetryAdapter.with_retry(fun,
               max_attempts: 1,
               retry_on: retry_on,
               sleep_fun: fn _ -> :ok end
             )
  end

  test "uses retry_after_ms_fun for delay overrides" do
    parent = self()

    fun = fn ->
      attempt = Process.get(:attempt, 0)
      Process.put(:attempt, attempt + 1)

      if attempt < 1 do
        {:ok, :retry}
      else
        {:ok, :done}
      end
    end

    retry_on = fn
      {:ok, :retry} -> true
      _ -> false
    end

    retry_after_ms_fun = fn
      {:ok, :retry} -> 25
      _ -> nil
    end

    sleep_fun = fn ms -> send(parent, {:slept, ms}) end

    assert {:ok, :done} =
             RetryAdapter.with_retry(fun,
               max_attempts: 1,
               retry_on: retry_on,
               retry_after_ms_fun: retry_after_ms_fun,
               sleep_fun: sleep_fun
             )

    assert_received {:slept, 25}
  end

  test "halts when max_elapsed_ms is exceeded before attempts" do
    parent = self()

    time_fun = fn :millisecond ->
      call = Process.get(:time_call, 0)
      Process.put(:time_call, call + 1)
      100 + call
    end

    fun = fn ->
      send(parent, :called)
      {:ok, :done}
    end

    assert {:error, :max_elapsed} =
             RetryAdapter.with_retry(fun,
               max_attempts: 1,
               retry_on: fn _ -> true end,
               max_elapsed_ms: 0,
               time_fun: time_fun,
               sleep_fun: fn _ -> :ok end
             )

    refute_received :called
  end
end
