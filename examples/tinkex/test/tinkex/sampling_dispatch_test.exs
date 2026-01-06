defmodule Tinkex.SamplingDispatchTest do
  use ExUnit.Case, async: false

  alias Tinkex.{RateLimiter, SamplingDispatch, Semaphore}

  setup do
    # Ensure ETS table exists for rate limiters
    if :ets.whereis(:tinkex_rate_limiters) == :undefined do
      :ets.new(:tinkex_rate_limiters, [:set, :public, :named_table])
    end

    # Ensure Semaphore is started (restart if dead)
    case GenServer.whereis(Semaphore) do
      nil ->
        {:ok, _} = Semaphore.start_link()

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          GenServer.call(pid, :reset)
        else
          {:ok, _} = Semaphore.start_link()
        end
    end

    :ok
  end

  describe "start_link/1" do
    test "starts with required options" do
      limiter = RateLimiter.for_key({unique_url(), "key"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "test-key"
        )

      assert is_pid(dispatch)
    end

    test "accepts custom concurrency options" do
      limiter = RateLimiter.for_key({unique_url(), "key2"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "test-key",
          concurrency: 50,
          throttled_concurrency: 5,
          byte_budget: 1_000_000
        )

      assert is_pid(dispatch)
    end
  end

  describe "with_rate_limit/3" do
    test "executes function and returns result" do
      limiter = RateLimiter.for_key({unique_url(), "k"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k",
          byte_budget: 1_000_000,
          concurrency: 10,
          throttled_concurrency: 5
        )

      result =
        SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
          :result
        end)

      assert result == :result
    end

    test "executes without throttling when no backoff" do
      limiter = RateLimiter.for_key({unique_url(), "k2"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k2",
          byte_budget: 1_000_000,
          concurrency: 2,
          throttled_concurrency: 2
        )

      result =
        SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
          :result
        end)

      assert result == :result
    end

    test "applies 20x byte penalty during recent backoff" do
      limiter = RateLimiter.for_key({unique_url(), "k"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k",
          byte_budget: 1_000,
          concurrency: 2,
          throttled_concurrency: 2
        )

      SamplingDispatch.set_backoff(dispatch, 10_000)

      parent = self()

      task1 =
        Task.async(fn ->
          SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
            send(parent, :task1_acquired)

            receive do
              :release_task1 -> :ok
            end

            :done
          end)
        end)

      assert_receive :task1_acquired, 500

      task2 =
        Task.async(fn ->
          SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
            send(parent, :task2_acquired)
            :done
          end)
        end)

      # Penalty drives effective bytes beyond budget so second task should block until release
      refute_receive :task2_acquired, 20

      send(task1.pid, :release_task1)

      assert_receive :task2_acquired, 500

      assert :done = Task.await(task1, 1_000)
      assert :done = Task.await(task2, 1_000)
    end

    test "handles negative estimated bytes" do
      limiter = RateLimiter.for_key({unique_url(), "neg"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-neg",
          byte_budget: 1_000,
          concurrency: 2,
          throttled_concurrency: 2
        )

      result =
        SamplingDispatch.with_rate_limit(dispatch, -100, fn ->
          :ok
        end)

      assert result == :ok
    end
  end

  describe "set_backoff/2" do
    test "sets backoff and marks as recently throttled" do
      limiter = RateLimiter.for_key({unique_url(), "kb"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-kb",
          byte_budget: 1_000_000,
          concurrency: 10,
          throttled_concurrency: 5
        )

      assert :ok = SamplingDispatch.set_backoff(dispatch, 1000)
    end

    test "accepts zero duration" do
      limiter = RateLimiter.for_key({unique_url(), "kz"})

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-kz",
          byte_budget: 1_000_000,
          concurrency: 10,
          throttled_concurrency: 5
        )

      assert :ok = SamplingDispatch.set_backoff(dispatch, 0)
    end
  end

  describe "acquire backoff" do
    test "acquires with jittered exponential backoff when busy" do
      limiter = RateLimiter.for_key({unique_url(), "k3"})
      parent = self()
      attempts = :atomics.new(1, [])

      acquire_fun = fn _name, _limit ->
        attempt = :atomics.add_get(attempts, 1, 1)
        attempt > 3
      end

      sleep_fun = fn ms -> send(parent, {:slept, ms}) end

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k3",
          byte_budget: 1_000_000,
          concurrency: 1,
          throttled_concurrency: 1,
          acquire_backoff: [
            base_ms: 2,
            max_ms: 20,
            jitter: 0.0,
            sleep_fun: sleep_fun,
            acquire_fun: acquire_fun,
            release_fun: fn _name -> :ok end,
            rand_fun: fn -> 0.0 end
          ]
        )

      assert :ok == SamplingDispatch.with_rate_limit(dispatch, 0, fn -> :ok end)
      assert_receive {:slept, 2}
      assert_receive {:slept, 4}
      assert_receive {:slept, 8}
      refute_receive {:slept, _}
    end

    test "backoff delay is capped at max_ms" do
      limiter = RateLimiter.for_key({unique_url(), "k4"})
      parent = self()
      attempts = :atomics.new(1, [])

      acquire_fun = fn _name, _limit ->
        attempt = :atomics.add_get(attempts, 1, 1)
        attempt > 10
      end

      sleep_fun = fn ms -> send(parent, {:slept, ms}) end

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k4",
          byte_budget: 1_000_000,
          concurrency: 1,
          throttled_concurrency: 1,
          acquire_backoff: [
            base_ms: 2,
            max_ms: 10,
            jitter: 0.0,
            sleep_fun: sleep_fun,
            acquire_fun: acquire_fun,
            release_fun: fn _name -> :ok end,
            rand_fun: fn -> 0.0 end
          ]
        )

      assert :ok == SamplingDispatch.with_rate_limit(dispatch, 0, fn -> :ok end)

      # Collect all sleep messages
      sleeps = collect_sleeps([])

      # All delays should be <= max_ms (10)
      assert Enum.all?(sleeps, &(&1 <= 10))
      # Should have exponential growth until cap: 2, 4, 8, 10, 10, 10, ...
      assert hd(sleeps) == 2
    end

    test "jitter varies delay" do
      limiter = RateLimiter.for_key({unique_url(), "k5"})
      parent = self()
      attempts = :atomics.new(1, [])
      rand_value = :atomics.new(1, signed: false)

      acquire_fun = fn _name, _limit ->
        attempt = :atomics.add_get(attempts, 1, 1)
        attempt > 2
      end

      sleep_fun = fn ms -> send(parent, {:slept, ms}) end

      rand_fun = fn ->
        # Alternate between 0 and 1
        val = :atomics.add_get(rand_value, 1, 1)
        if rem(val, 2) == 0, do: 1.0, else: 0.0
      end

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-k5",
          byte_budget: 1_000_000,
          concurrency: 1,
          throttled_concurrency: 1,
          acquire_backoff: [
            base_ms: 10,
            max_ms: 100,
            jitter: 0.5,
            sleep_fun: sleep_fun,
            acquire_fun: acquire_fun,
            release_fun: fn _name -> :ok end,
            rand_fun: rand_fun
          ]
        )

      assert :ok == SamplingDispatch.with_rate_limit(dispatch, 0, fn -> :ok end)

      sleeps = collect_sleeps([])
      # With jitter 0.5, delays should vary
      assert length(sleeps) == 2
    end
  end

  describe "throttled concurrency" do
    test "uses throttled semaphore during backoff" do
      limiter = RateLimiter.for_key({unique_url(), "kt"})
      parent = self()

      {:ok, dispatch} =
        SamplingDispatch.start_link(
          rate_limiter: limiter,
          base_url: unique_url(),
          api_key: "tml-kt",
          byte_budget: 10_000_000,
          concurrency: 100,
          # Very limited throttled concurrency
          throttled_concurrency: 1
        )

      # Trigger backoff
      SamplingDispatch.set_backoff(dispatch, 10_000)

      # First request should acquire throttled semaphore
      task1 =
        Task.async(fn ->
          SamplingDispatch.with_rate_limit(dispatch, 0, fn ->
            send(parent, :t1_in)

            receive do
              :release -> :done
            end
          end)
        end)

      assert_receive :t1_in, 500

      # Second request should block on throttled semaphore
      task2 =
        Task.async(fn ->
          SamplingDispatch.with_rate_limit(dispatch, 0, fn ->
            send(parent, :t2_in)
            :done
          end)
        end)

      refute_receive :t2_in, 50

      send(task1.pid, :release)
      assert_receive :t2_in, 500

      Task.await(task1)
      Task.await(task2)
    end
  end

  defp unique_url do
    "https://example#{:erlang.unique_integer([:positive])}.com"
  end

  defp collect_sleeps(acc) do
    receive do
      {:slept, ms} -> collect_sleeps([ms | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end
end
