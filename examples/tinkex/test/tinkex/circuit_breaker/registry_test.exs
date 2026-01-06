defmodule Tinkex.CircuitBreaker.RegistryTest do
  @moduledoc """
  Tests for the ETS-based circuit breaker registry.
  """
  use ExUnit.Case

  alias Tinkex.CircuitBreaker.Registry

  setup do
    # Initialize registry for each test
    Registry.init()
    # Clean up test entries
    Registry.delete("test-endpoint")
    Registry.delete("test-concurrent")
    :ok
  end

  describe "init/0" do
    test "creates the ETS table" do
      # Table already created in setup
      assert :ets.whereis(:tinkex_circuit_breakers) != :undefined
    end

    test "is idempotent" do
      assert Registry.init() == :ok
      assert Registry.init() == :ok
    end
  end

  describe "call/3" do
    test "executes function through circuit breaker" do
      result =
        Registry.call("test-endpoint", fn ->
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
    end

    test "creates circuit breaker if it doesn't exist" do
      Registry.delete("test-endpoint")

      Registry.call("test-endpoint", fn ->
        {:ok, "success"}
      end)

      assert Registry.state("test-endpoint") == :closed
    end

    test "records failures and opens circuit" do
      # Configure with low threshold
      for _ <- 1..5 do
        Registry.call("test-endpoint", fn ->
          {:error, "failed"}
        end)
      end

      # Circuit should be open now
      result =
        Registry.call("test-endpoint", fn ->
          {:ok, "should not run"}
        end)

      assert result == {:error, :circuit_open}
    end

    test "respects custom failure threshold" do
      # Use custom threshold of 2
      Registry.delete("test-endpoint")

      for _ <- 1..2 do
        Registry.call(
          "test-endpoint",
          fn -> {:error, "failed"} end,
          failure_threshold: 2
        )
      end

      result =
        Registry.call("test-endpoint", fn ->
          {:ok, "should not run"}
        end)

      assert result == {:error, :circuit_open}
    end

    test "applies custom success classifier" do
      # 4xx errors should not count as failures
      success_fn = fn
        {:ok, _} -> true
        {:error, %{status: status}} when status < 500 -> true
        _ -> false
      end

      for _ <- 1..5 do
        Registry.call(
          "test-endpoint",
          fn -> {:error, %{status: 400}} end,
          success?: success_fn
        )
      end

      # Circuit should still be closed (400 errors classified as success)
      assert Registry.state("test-endpoint") == :closed
    end
  end

  describe "state/1" do
    test "returns :closed for non-existent circuit breaker" do
      Registry.delete("non-existent")
      assert Registry.state("non-existent") == :closed
    end

    test "returns current state" do
      Registry.call("test-endpoint", fn -> {:ok, "success"} end)
      assert Registry.state("test-endpoint") == :closed
    end

    test "returns :open when circuit is open" do
      Registry.delete("test-endpoint")

      for _ <- 1..5 do
        Registry.call("test-endpoint", fn -> {:error, "failed"} end)
      end

      assert Registry.state("test-endpoint") == :open
    end
  end

  describe "reset/1" do
    test "resets circuit to closed state" do
      Registry.delete("test-endpoint")

      for _ <- 1..5 do
        Registry.call("test-endpoint", fn -> {:error, "failed"} end)
      end

      assert Registry.state("test-endpoint") == :open

      Registry.reset("test-endpoint")

      assert Registry.state("test-endpoint") == :closed
    end

    test "is safe to call on non-existent circuit" do
      Registry.delete("non-existent")
      assert Registry.reset("non-existent") == :ok
    end
  end

  describe "delete/1" do
    test "removes circuit breaker from registry" do
      Registry.call("test-endpoint", fn -> {:ok, "success"} end)
      Registry.delete("test-endpoint")

      # Should be gone
      assert Registry.state("test-endpoint") == :closed

      # Should create new one
      Registry.call("test-endpoint", fn -> {:ok, "success"} end)
      [{name, _}] = Registry.list() |> Enum.filter(fn {n, _} -> n == "test-endpoint" end)
      assert name == "test-endpoint"
    end
  end

  describe "list/0" do
    test "returns all circuit breakers" do
      Registry.call("test-endpoint", fn -> {:ok, "success"} end)

      list = Registry.list()
      assert is_list(list)

      # Find our test endpoint
      test_entry = Enum.find(list, fn {name, _state} -> name == "test-endpoint" end)
      assert test_entry != nil
      assert elem(test_entry, 1) == :closed
    end
  end

  describe "concurrent access" do
    test "handles concurrent calls safely" do
      Registry.delete("test-concurrent")

      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            Registry.call("test-concurrent", fn ->
              # Small delay to increase chance of contention
              Process.sleep(1)
              {:ok, "success"}
            end)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn result -> result == {:ok, "success"} end)

      # State should be consistent
      assert Registry.state("test-concurrent") == :closed
    end

    test "handles concurrent failures correctly" do
      Registry.delete("test-concurrent")

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Registry.call(
              "test-concurrent",
              fn -> {:error, "failed"} end,
              failure_threshold: 5
            )
          end)
        end

      Task.await_many(tasks)

      # Circuit should be open after 5+ failures
      assert Registry.state("test-concurrent") == :open
    end
  end
end
