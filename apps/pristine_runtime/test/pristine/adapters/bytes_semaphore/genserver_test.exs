defmodule Pristine.Adapters.BytesSemaphore.GenServerTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.BytesSemaphore.GenServer, as: BytesSemaphore

  describe "start_link/1" do
    test "starts with default max_bytes (5MB)" do
      {:ok, sem} = BytesSemaphore.start_link([])
      assert BytesSemaphore.available(sem) == 5 * 1024 * 1024
    end

    test "starts with custom max_bytes" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)
      assert BytesSemaphore.available(sem) == 1000
    end

    test "starts with name registration" do
      name = :"test_sem_#{:erlang.unique_integer([:positive])}"
      {:ok, _sem} = BytesSemaphore.start_link(max_bytes: 500, name: name)
      assert BytesSemaphore.available(name) == 500
    end
  end

  describe "acquire/3" do
    test "acquires bytes and reduces available count" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      assert :ok = BytesSemaphore.acquire(sem, 300, 5_000)
      assert BytesSemaphore.available(sem) == 700

      assert :ok = BytesSemaphore.acquire(sem, 200, 5_000)
      assert BytesSemaphore.available(sem) == 500
    end

    test "allows budget to go negative" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # First acquire goes through immediately
      assert :ok = BytesSemaphore.acquire(sem, 150, 5_000)
      # Budget is now -50, available returns 0
      assert BytesSemaphore.available(sem) == 0
    end

    test "blocks when budget is negative and times out" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # Push budget negative
      assert :ok = BytesSemaphore.acquire(sem, 150, 5_000)

      # New acquire should block and timeout
      assert {:error, :timeout} = BytesSemaphore.acquire(sem, 50, 100)
    end

    test "acquire with zero bytes succeeds" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)
      assert :ok = BytesSemaphore.acquire(sem, 0, 5_000)
      assert BytesSemaphore.available(sem) == 100
    end
  end

  describe "release/2" do
    test "releases bytes and increases available count" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      :ok = BytesSemaphore.acquire(sem, 300, 5_000)
      assert BytesSemaphore.available(sem) == 700

      :ok = BytesSemaphore.release(sem, 300)
      assert BytesSemaphore.available(sem) == 1000
    end

    test "release wakes blocked waiters" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # Push budget negative
      :ok = BytesSemaphore.acquire(sem, 150, 5_000)

      # Start a task that will block
      parent = self()

      task =
        Task.async(fn ->
          send(parent, :waiting)
          result = BytesSemaphore.acquire(sem, 50, 5_000)
          send(parent, {:acquired, result})
          result
        end)

      # Wait for task to start waiting
      assert_receive :waiting, 1_000

      # Release enough to bring budget non-negative
      :ok = BytesSemaphore.release(sem, 100)

      # Task should now complete
      assert_receive {:acquired, :ok}, 1_000
      assert Task.await(task) == :ok
    end
  end

  describe "available/1" do
    test "returns max_bytes when no acquisitions" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 5000)
      assert BytesSemaphore.available(sem) == 5000
    end

    test "returns 0 when budget is negative" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)
      :ok = BytesSemaphore.acquire(sem, 200, 5_000)
      assert BytesSemaphore.available(sem) == 0
    end

    test "tracks multiple acquisitions and releases" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      :ok = BytesSemaphore.acquire(sem, 100, 5_000)
      assert BytesSemaphore.available(sem) == 900

      :ok = BytesSemaphore.acquire(sem, 200, 5_000)
      assert BytesSemaphore.available(sem) == 700

      :ok = BytesSemaphore.release(sem, 150)
      assert BytesSemaphore.available(sem) == 850

      :ok = BytesSemaphore.release(sem, 150)
      assert BytesSemaphore.available(sem) == 1000
    end
  end

  describe "with_bytes/3" do
    test "acquires, executes function, and releases" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      result =
        BytesSemaphore.with_bytes(sem, 300, fn ->
          assert BytesSemaphore.available(sem) == 700
          :test_result
        end)

      assert result == :test_result
      assert BytesSemaphore.available(sem) == 1000
    end

    test "releases even when function raises" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      assert_raise RuntimeError, "test error", fn ->
        BytesSemaphore.with_bytes(sem, 300, fn ->
          raise "test error"
        end)
      end

      assert BytesSemaphore.available(sem) == 1000
    end

    test "releases even when function throws" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      catch_throw(
        BytesSemaphore.with_bytes(sem, 300, fn ->
          throw(:test_throw)
        end)
      )

      assert BytesSemaphore.available(sem) == 1000
    end

    test "releases even when function exits" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      catch_exit(
        BytesSemaphore.with_bytes(sem, 300, fn ->
          exit(:test_exit)
        end)
      )

      assert BytesSemaphore.available(sem) == 1000
    end
  end

  describe "blocking behavior" do
    test "multiple waiters are served in FIFO order" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # Push budget negative
      :ok = BytesSemaphore.acquire(sem, 150, 5_000)

      parent = self()

      # Start two tasks that will block
      task1 =
        Task.async(fn ->
          send(parent, {:task1, :waiting})
          result = BytesSemaphore.acquire(sem, 30, 10_000)
          send(parent, {:task1, :acquired})
          result
        end)

      # Ensure task1 is waiting first
      assert_receive {:task1, :waiting}, 1_000
      Process.sleep(50)

      task2 =
        Task.async(fn ->
          send(parent, {:task2, :waiting})
          result = BytesSemaphore.acquire(sem, 20, 10_000)
          send(parent, {:task2, :acquired})
          result
        end)

      assert_receive {:task2, :waiting}, 1_000

      # Release enough to bring budget non-negative and serve both waiters
      # Budget: -50 + 100 = 50 (positive, task1 gets 30) -> 20 (task2 gets 20) -> 0
      :ok = BytesSemaphore.release(sem, 100)

      # task1 should be served first (FIFO)
      assert_receive {:task1, :acquired}, 1_000
      assert_receive {:task2, :acquired}, 1_000

      assert Task.await(task1) == :ok
      assert Task.await(task2) == :ok
    end

    test "waiters timeout individually" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # Push budget negative
      :ok = BytesSemaphore.acquire(sem, 150, 5_000)

      parent = self()

      # Start a task with short timeout
      task1 =
        Task.async(fn ->
          result = BytesSemaphore.acquire(sem, 30, 100)
          send(parent, {:task1, result})
          result
        end)

      # Start a task with longer timeout
      task2 =
        Task.async(fn ->
          result = BytesSemaphore.acquire(sem, 20, 5_000)
          send(parent, {:task2, result})
          result
        end)

      # task1 should timeout
      assert_receive {:task1, {:error, :timeout}}, 500

      # Release to let task2 proceed
      :ok = BytesSemaphore.release(sem, 100)
      assert_receive {:task2, :ok}, 1_000

      assert Task.await(task1) == {:error, :timeout}
      assert Task.await(task2) == :ok
    end
  end

  describe "concurrent operations" do
    test "handles many concurrent acquire/release cycles" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 10_000)

      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            bytes = 100 + rem(i * 17, 400)

            BytesSemaphore.with_bytes(sem, bytes, fn ->
              Process.sleep(:rand.uniform(10))
              {:ok, i}
            end)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All tasks should complete
      assert length(results) == 20
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # All bytes should be released
      assert BytesSemaphore.available(sem) == 10_000
    end
  end
end
