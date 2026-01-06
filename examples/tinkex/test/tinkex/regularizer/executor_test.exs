defmodule Tinkex.Regularizer.ExecutorTest do
  @moduledoc """
  Tests for regularizer execution with process-based parallelism.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.Executor
  alias Tinkex.Types.{RegularizerOutput, RegularizerSpec}

  describe "execute_all/4" do
    test "returns empty list for empty regularizers" do
      assert {:ok, []} = Executor.execute_all([], [], Nx.tensor([1.0]), [])
    end

    test "executes single regularizer" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "test"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, [])

      assert length(outputs) == 1
      [output] = outputs
      assert output.name == "test"
      assert_in_delta output.value, 6.0, 0.001
      assert_in_delta output.contribution, 0.6, 0.001
    end

    test "executes multiple regularizers" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "sum"
        },
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.mean(logprobs), %{}} end,
          weight: 0.2,
          name: "mean"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, [])

      assert length(outputs) == 2
      names = Enum.map(outputs, & &1.name)
      assert "sum" in names
      assert "mean" in names
    end

    test "executes in parallel by default" do
      # Use a slow regularizer to verify parallel execution
      regularizers =
        for i <- 1..3 do
          %RegularizerSpec{
            fn: fn _data, logprobs ->
              Process.sleep(50)
              {Nx.sum(logprobs), %{"index" => i}}
            end,
            weight: 0.1,
            name: "reg_#{i}"
          }
        end

      data = []
      logprobs = Nx.tensor([1.0])

      start = System.monotonic_time(:millisecond)
      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, parallel: true)
      elapsed = System.monotonic_time(:millisecond) - start

      assert length(outputs) == 3
      # Parallel should be faster than 150ms (3 * 50ms)
      assert elapsed < 150
    end

    test "executes sequentially when parallel: false" do
      regularizers =
        for i <- 1..3 do
          %RegularizerSpec{
            fn: fn _data, logprobs ->
              Process.sleep(30)
              {Nx.sum(logprobs), %{"index" => i}}
            end,
            weight: 0.1,
            name: "reg_#{i}"
          }
        end

      data = []
      logprobs = Nx.tensor([1.0])

      start = System.monotonic_time(:millisecond)
      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, parallel: false)
      elapsed = System.monotonic_time(:millisecond) - start

      assert length(outputs) == 3
      # Sequential should take at least 90ms (3 * 30ms)
      assert elapsed >= 90
    end

    test "tracks gradient norms when enabled" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "test"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, track_grad_norms: true)

      [output] = outputs
      assert output.grad_norm != nil
      assert_in_delta output.grad_norm, :math.sqrt(3), 0.001
    end

    test "does not track gradient norms by default" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "test"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0])

      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs, [])

      [output] = outputs
      assert output.grad_norm == nil
    end

    test "returns error on regularizer failure in sequential mode" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, _logprobs -> raise "boom" end,
          weight: 0.1,
          name: "failing"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0])

      assert {:error, {:regularizer_failed, "failing", %RuntimeError{}}} =
               Executor.execute_all(regularizers, data, logprobs, parallel: false)
    end
  end

  describe "execute_one/4" do
    test "executes regularizer and returns output" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs -> {Nx.sum(logprobs), %{"test" => 1}} end,
        weight: 0.5,
        name: "my_reg"
      }

      data = []
      logprobs = Nx.tensor([2.0, 3.0])

      {:ok, output} = Executor.execute_one(spec, data, logprobs, [])

      assert %RegularizerOutput{} = output
      assert output.name == "my_reg"
      assert_in_delta output.value, 5.0, 0.001
      assert output.weight == 0.5
      assert_in_delta output.contribution, 2.5, 0.001
      assert output.custom == %{"test" => 1}
    end

    test "handles async regularizers" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs ->
          Task.async(fn ->
            Process.sleep(10)
            {Nx.sum(logprobs), %{"async" => true}}
          end)
        end,
        weight: 0.1,
        name: "async_reg",
        async: true
      }

      data = []
      logprobs = Nx.tensor([1.0, 2.0])

      {:ok, output} = Executor.execute_one(spec, data, logprobs, timeout: 5000)

      assert output.name == "async_reg"
      assert_in_delta output.value, 3.0, 0.001
    end

    test "returns error on exception" do
      spec = %RegularizerSpec{
        fn: fn _data, _logprobs -> raise "computation error" end,
        weight: 0.1,
        name: "bad_reg"
      }

      data = []
      logprobs = Nx.tensor([1.0])

      assert {:error, {:regularizer_failed, "bad_reg", %RuntimeError{}}} =
               Executor.execute_one(spec, data, logprobs, [])
    end

    test "returns error on exit" do
      spec = %RegularizerSpec{
        fn: fn _data, _logprobs -> exit(:shutdown) end,
        weight: 0.1,
        name: "exiting_reg"
      }

      data = []
      logprobs = Nx.tensor([1.0])

      assert {:error, {:regularizer_exit, "exiting_reg", :shutdown}} =
               Executor.execute_one(spec, data, logprobs, [])
    end

    test "passes data to regularizer" do
      spec = %RegularizerSpec{
        fn: fn data, logprobs ->
          scale = length(data)
          {Nx.multiply(Nx.sum(logprobs), scale), %{}}
        end,
        weight: 1.0,
        name: "data_aware"
      }

      # length = 3
      data = [:a, :b, :c]
      logprobs = Nx.tensor([2.0])

      {:ok, output} = Executor.execute_one(spec, data, logprobs, [])

      assert_in_delta output.value, 6.0, 0.001
    end
  end
end
