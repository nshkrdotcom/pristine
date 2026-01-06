defmodule Tinkex.RetrySemaphoreTest do
  use ExUnit.Case, async: false

  alias Tinkex.RetrySemaphore

  setup do
    # Start semaphores with default names - handle already_started gracefully
    # since other tests or ensure_started might have started them
    sem_result = Tinkex.Semaphore.start_link()

    sem_pid =
      case sem_result do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    retry_result = RetrySemaphore.start_link()

    retry_pid =
      case retry_result do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # Don't stop on exit - other tests might need these running
    # The semaphores are stateless for our tests anyway
    %{pid: retry_pid, sem_pid: sem_pid}
  end

  describe "get_semaphore/1" do
    test "returns semaphore name tuple for max_connections" do
      name = RetrySemaphore.get_semaphore(10)
      assert {:tinkex_retry, {:default, 10}, 10} = name
    end
  end

  describe "get_semaphore/2" do
    test "returns semaphore name tuple for key and max_connections" do
      name = RetrySemaphore.get_semaphore(:my_key, 5)
      assert {:tinkex_retry, :my_key, 5} = name
    end
  end

  describe "with_semaphore/2" do
    test "executes function and returns result" do
      result = RetrySemaphore.with_semaphore(10, fn -> :done end)
      assert result == :done
    end

    test "releases semaphore after function completes" do
      # Execute multiple times to verify release
      for _ <- 1..5 do
        result = RetrySemaphore.with_semaphore(2, fn -> :ok end)
        assert result == :ok
      end
    end

    test "releases semaphore even on exception" do
      assert_raise RuntimeError, fn ->
        RetrySemaphore.with_semaphore(10, fn -> raise "error" end)
      end

      # Should still work after exception
      result = RetrySemaphore.with_semaphore(10, fn -> :recovered end)
      assert result == :recovered
    end
  end

  describe "with_semaphore/3 (key, max, fun)" do
    test "executes function with keyed semaphore" do
      result = RetrySemaphore.with_semaphore(:custom_key, 10, fn -> :keyed end)
      assert result == :keyed
    end
  end

  describe "with_semaphore/4 (key, max, opts, fun)" do
    test "accepts custom backoff options" do
      opts = [backoff: %{base_ms: 1, max_ms: 5}]
      result = RetrySemaphore.with_semaphore(:key, 10, opts, fn -> :custom end)
      assert result == :custom
    end
  end
end
