defmodule Tinkex.SemaphoreTest do
  use ExUnit.Case, async: false

  alias Tinkex.Semaphore

  setup do
    # Ensure Semaphore is started
    case GenServer.whereis(Semaphore) do
      nil ->
        {:ok, _} = Semaphore.start_link()

      pid ->
        # Reset state for clean tests
        GenServer.call(pid, :reset)
    end

    :ok
  end

  describe "start_link/0" do
    test "starts the semaphore server" do
      # Already started in setup
      assert is_pid(GenServer.whereis(Semaphore))
    end

    test "returns already_started if already running" do
      {:error, {:already_started, _pid}} = Semaphore.start_link()
    end
  end

  describe "acquire/2" do
    test "returns true when under limit" do
      assert Semaphore.acquire(:test_key, 3) == true
    end

    test "returns true up to limit" do
      assert Semaphore.acquire(:limit_test, 2) == true
      assert Semaphore.acquire(:limit_test, 2) == true
    end

    test "returns false when at limit" do
      assert Semaphore.acquire(:at_limit, 2) == true
      assert Semaphore.acquire(:at_limit, 2) == true
      assert Semaphore.acquire(:at_limit, 2) == false
    end

    test "different keys are independent" do
      assert Semaphore.acquire(:key_a, 1) == true
      assert Semaphore.acquire(:key_a, 1) == false
      assert Semaphore.acquire(:key_b, 1) == true
    end

    test "limit can be changed per call" do
      assert Semaphore.acquire(:flex_limit, 2) == true
      assert Semaphore.acquire(:flex_limit, 2) == true
      # Now at 2, try with limit 3 - should succeed
      assert Semaphore.acquire(:flex_limit, 3) == true
      # Now at 3, try with limit 3 - should fail
      assert Semaphore.acquire(:flex_limit, 3) == false
    end
  end

  describe "release/1" do
    test "returns :ok" do
      Semaphore.acquire(:release_test, 1)
      assert Semaphore.release(:release_test) == :ok
    end

    test "allows re-acquisition after release" do
      assert Semaphore.acquire(:reacquire, 1) == true
      assert Semaphore.acquire(:reacquire, 1) == false
      Semaphore.release(:reacquire)
      assert Semaphore.acquire(:reacquire, 1) == true
    end

    test "does not go below zero" do
      # Release without acquire
      Semaphore.release(:no_acquire)
      # Should still be able to acquire
      assert Semaphore.acquire(:no_acquire, 1) == true
    end

    test "multiple releases work correctly" do
      Semaphore.acquire(:multi_release, 2)
      Semaphore.acquire(:multi_release, 2)
      assert Semaphore.acquire(:multi_release, 2) == false

      Semaphore.release(:multi_release)
      assert Semaphore.acquire(:multi_release, 2) == true
      assert Semaphore.acquire(:multi_release, 2) == false

      Semaphore.release(:multi_release)
      Semaphore.release(:multi_release)
      assert Semaphore.acquire(:multi_release, 2) == true
      assert Semaphore.acquire(:multi_release, 2) == true
    end
  end

  describe "count/1" do
    test "returns current count for key" do
      assert Semaphore.count(:count_test) == 0
      Semaphore.acquire(:count_test, 5)
      assert Semaphore.count(:count_test) == 1
      Semaphore.acquire(:count_test, 5)
      assert Semaphore.count(:count_test) == 2
    end

    test "decrements on release" do
      Semaphore.acquire(:count_dec, 5)
      Semaphore.acquire(:count_dec, 5)
      assert Semaphore.count(:count_dec) == 2
      Semaphore.release(:count_dec)
      assert Semaphore.count(:count_dec) == 1
    end
  end

  describe "concurrent access" do
    test "handles concurrent acquires correctly" do
      limit = 5

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Semaphore.acquire(:concurrent, limit)
          end)
        end

      results = Task.await_many(tasks, 1000)

      # Exactly `limit` should succeed
      assert Enum.count(results, & &1) == limit
      assert Enum.count(results, &(!&1)) == 5
    end

    test "handles concurrent acquire and release" do
      Semaphore.acquire(:conc_release, 1)

      task =
        Task.async(fn ->
          # Small delay to ensure release happens after acquire attempt
          Process.sleep(10)
          Semaphore.release(:conc_release)
        end)

      # First attempt fails
      assert Semaphore.acquire(:conc_release, 1) == false

      Task.await(task)

      # After release, should succeed
      assert Semaphore.acquire(:conc_release, 1) == true
    end
  end
end
