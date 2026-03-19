defmodule Pristine.Adapters.Semaphore.CountingTest do
  use ExUnit.Case, async: false

  alias Pristine.Adapters.Semaphore.Counting

  setup do
    # Generate unique name for each test to avoid state leakage
    name = :"test_sem_#{:erlang.unique_integer([:positive])}"
    {:ok, name: name}
  end

  describe "init/2" do
    test "initializes a semaphore with the given limit", %{name: name} do
      assert :ok = Counting.init(name, 5)
      assert Counting.available(name) == 5
    end

    test "raises for invalid limit" do
      assert_raise FunctionClauseError, fn ->
        Counting.init(:invalid_limit, 0)
      end

      assert_raise FunctionClauseError, fn ->
        Counting.init(:negative_limit, -1)
      end
    end
  end

  describe "with_permit/3" do
    test "executes function and returns result", %{name: name} do
      Counting.init(name, 2)

      result =
        Counting.with_permit(name, 5_000, fn ->
          :test_result
        end)

      assert result == :test_result
    end

    test "releases permit after function completes", %{name: name} do
      Counting.init(name, 2)

      Counting.with_permit(name, 5_000, fn ->
        assert Counting.available(name) == 1
      end)

      assert Counting.available(name) == 2
    end

    test "releases permit even when function raises", %{name: name} do
      Counting.init(name, 2)

      assert_raise RuntimeError, "test error", fn ->
        Counting.with_permit(name, 5_000, fn ->
          raise "test error"
        end)
      end

      assert Counting.available(name) == 2
    end

    test "limits concurrent executions", %{name: name} do
      Counting.init(name, 2)

      # Track concurrent executions
      counter = :counters.new(1, [:atomics])
      max_concurrent = :counters.new(1, [:atomics])

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Counting.with_permit(name, 10_000, fn ->
              :counters.add(counter, 1, 1)
              current = :counters.get(counter, 1)

              # Update max if current is higher
              current_max = :counters.get(max_concurrent, 1)
              if current > current_max, do: :counters.put(max_concurrent, 1, current)

              Process.sleep(20)
              :counters.sub(counter, 1, 1)
              :ok
            end)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))

      # Max concurrent should never exceed limit
      assert :counters.get(max_concurrent, 1) <= 2
    end

    test "returns timeout error when limit reached", %{name: name} do
      Counting.init(name, 1)

      # Acquire the only permit in a background task
      task =
        Task.async(fn ->
          Counting.with_permit(name, :infinity, fn ->
            Process.sleep(1_000)
            :ok
          end)
        end)

      # Wait for task to acquire permit
      Process.sleep(50)

      # Try to acquire with short timeout - should fail
      assert {:error, :timeout} = Counting.with_permit(name, 10, fn -> :ok end)

      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "acquire/2 and release/1" do
    test "acquires and releases permits", %{name: name} do
      Counting.init(name, 3)

      assert Counting.available(name) == 3

      assert :ok = Counting.acquire(name, 1_000)
      assert Counting.available(name) == 2

      assert :ok = Counting.acquire(name, 1_000)
      assert Counting.available(name) == 1

      assert :ok = Counting.release(name)
      assert Counting.available(name) == 2

      assert :ok = Counting.release(name)
      assert Counting.available(name) == 3
    end

    test "acquire times out when no permits available", %{name: name} do
      Counting.init(name, 1)

      assert :ok = Counting.acquire(name, 1_000)
      assert {:error, :timeout} = Counting.acquire(name, 10)

      # Release and try again
      Counting.release(name)
      assert :ok = Counting.acquire(name, 1_000)
    end
  end

  describe "available/1" do
    test "returns correct available count", %{name: name} do
      Counting.init(name, 5)

      assert Counting.available(name) == 5

      Counting.with_permit(name, 1_000, fn ->
        assert Counting.available(name) == 4

        Counting.with_permit(name, 1_000, fn ->
          assert Counting.available(name) == 3
        end)

        assert Counting.available(name) == 4
      end)

      assert Counting.available(name) == 5
    end

    test "raises for uninitialized semaphore" do
      assert_raise ArgumentError, ~r/not initialized/, fn ->
        Counting.available(:uninitialized_sem)
      end
    end
  end

  describe "concurrent stress test" do
    test "handles many concurrent operations", %{name: name} do
      limit = 5
      Counting.init(name, limit)

      # Launch many concurrent tasks
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            result =
              Counting.with_permit(name, 5_000, fn ->
                # Verify we never exceed the limit
                available = Counting.available(name)
                assert available >= 0
                assert available < limit

                # Small random sleep to add variability
                Process.sleep(:rand.uniform(10))
                i
              end)

            result
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All tasks should complete with their index
      assert Enum.sort(results) == Enum.to_list(1..50)

      # All permits should be released
      assert Counting.available(name) == limit
    end
  end
end
