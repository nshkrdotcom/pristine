defmodule Tinkex.BytesSemaphoreTest do
  use ExUnit.Case, async: true

  alias Tinkex.BytesSemaphore

  describe "start_link/1" do
    test "starts with default max_bytes" do
      {:ok, sem} = BytesSemaphore.start_link()
      assert is_pid(sem)
    end

    test "starts with custom max_bytes" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)
      assert is_pid(sem)
    end

    test "accepts name option" do
      name = :"test_sem_#{:erlang.unique_integer([:positive])}"
      {:ok, sem} = BytesSemaphore.start_link(name: name)
      assert Process.whereis(name) == sem
    end
  end

  describe "acquire/2" do
    test "allows acquisition within budget" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      assert :ok = BytesSemaphore.acquire(sem, 500)
    end

    test "allows acquisition up to budget" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      assert :ok = BytesSemaphore.acquire(sem, 1000)
    end

    test "allows over-acquisition pushing budget negative" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      task1 = Task.async(fn -> BytesSemaphore.acquire(sem, 500) end)
      assert Task.await(task1) == :ok

      task2 = Task.async(fn -> BytesSemaphore.acquire(sem, 600) end)
      assert Task.await(task2) == :ok
    end

    test "blocks when budget is negative" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

      # Push budget negative
      BytesSemaphore.acquire(sem, 500)
      BytesSemaphore.acquire(sem, 600)

      # New acquisition should block
      task = Task.async(fn -> BytesSemaphore.acquire(sem, 100) end)
      refute Task.yield(task, 50)

      # Release to allow blocked task to proceed
      BytesSemaphore.release(sem, 500)
      assert Task.await(task) == :ok
    end

    test "accepts zero bytes" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)
      assert :ok = BytesSemaphore.acquire(sem, 0)
    end
  end

  describe "release/2" do
    test "releases bytes back to semaphore" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      BytesSemaphore.acquire(sem, 100)
      :ok = BytesSemaphore.release(sem, 100)

      # Should be able to acquire again
      assert :ok = BytesSemaphore.acquire(sem, 100)
    end

    test "wakes blocked waiters when budget returns positive" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      # Acquire full budget
      BytesSemaphore.acquire(sem, 100)

      # Push negative
      BytesSemaphore.acquire(sem, 50)

      # This should block
      task = Task.async(fn -> BytesSemaphore.acquire(sem, 25) end)
      refute Task.yield(task, 30)

      # Release should wake waiter
      BytesSemaphore.release(sem, 150)
      assert Task.await(task) == :ok
    end

    test "accepts zero bytes" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)
      :ok = BytesSemaphore.release(sem, 0)
    end
  end

  describe "with_bytes/3" do
    test "executes function and returns result" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      result = BytesSemaphore.with_bytes(sem, 50, fn -> :done end)
      assert result == :done
    end

    test "releases bytes on normal return" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      assert :done == BytesSemaphore.with_bytes(sem, 50, fn -> :done end)

      # Budget should be restored
      assert :ok == BytesSemaphore.acquire(sem, 100)
    end

    test "releases bytes on exception" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      assert_raise RuntimeError, fn ->
        BytesSemaphore.with_bytes(sem, 50, fn -> raise "oops" end)
      end

      # Budget should be restored
      assert :ok == BytesSemaphore.acquire(sem, 100)
    end

    test "releases bytes on throw" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      catch_throw(BytesSemaphore.with_bytes(sem, 50, fn -> throw(:ball) end))

      # Budget should be restored
      assert :ok == BytesSemaphore.acquire(sem, 100)
    end

    test "releases bytes on exit" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      catch_exit(BytesSemaphore.with_bytes(sem, 50, fn -> exit(:normal) end))

      # Budget should be restored
      assert :ok == BytesSemaphore.acquire(sem, 100)
    end
  end

  describe "integration" do
    test "multiple concurrent callers are properly serialized" do
      {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

      results =
        1..5
        |> Enum.map(fn i ->
          Task.async(fn ->
            BytesSemaphore.with_bytes(sem, 80, fn ->
              Process.sleep(10)
              i
            end)
          end)
        end)
        |> Task.await_many(2000)

      assert Enum.sort(results) == [1, 2, 3, 4, 5]
    end
  end
end
