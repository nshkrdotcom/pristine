defmodule Tinkex.Regularizer.PipelineTest do
  @moduledoc """
  Tests for regularizer pipeline orchestration.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.Pipeline
  alias Tinkex.Types.{CustomLossOutput, RegularizerSpec}

  describe "compute/4" do
    test "computes base loss only" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{"base" => 1.0}} end
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn)

      assert %CustomLossOutput{} = output
      assert_in_delta output.loss_total, 6.0, 0.001
      assert output.regularizer_total == 0
      assert output.regularizers == %{}
    end

    test "computes base loss with regularizers" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.mean(logprobs), %{}} end,
          weight: 0.1,
          name: "mean_reg"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # base = 6.0, reg = 2.0 * 0.1 = 0.2, total = 6.2
      assert_in_delta output.loss_total, 6.2, 0.001
      assert_in_delta output.regularizer_total, 0.2, 0.001
      assert Map.has_key?(output.regularizers, "mean_reg")
    end

    test "computes multiple regularizers" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.mean(logprobs), %{}} end,
          weight: 0.1,
          name: "r1"
        },
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(Nx.pow(logprobs, 2)), %{}} end,
          weight: 0.01,
          name: "r2"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # base = 6.0
      # r1 = 2.0 * 0.1 = 0.2
      # r2 = (1+4+9) * 0.01 = 0.14
      # total = 6.0 + 0.2 + 0.14 = 6.34
      assert_in_delta output.loss_total, 6.34, 0.001
      assert Map.has_key?(output.regularizers, "r1")
      assert Map.has_key?(output.regularizers, "r2")
    end

    test "tracks gradient norms when enabled" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "test"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn,
          regularizers: regularizers,
          track_grad_norms: true
        )

      assert output.base_loss.grad_norm != nil
      assert output.total_grad_norm != nil
      assert output.regularizers["test"].grad_norm != nil
    end

    test "does not track gradient norms by default" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end
      data = []
      logprobs = Nx.tensor([1.0])

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn)

      assert output.base_loss.grad_norm == nil
      assert output.total_grad_norm == nil
    end

    test "executes regularizers in parallel by default" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

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
      {:ok, _output} = Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should be faster than sequential (90ms)
      assert elapsed < 90
    end

    test "executes sequentially when parallel: false" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers =
        for i <- 1..2 do
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

      {:ok, _output} =
        Pipeline.compute(data, logprobs, base_loss_fn,
          regularizers: regularizers,
          parallel: false
        )

      elapsed = System.monotonic_time(:millisecond) - start

      # Should take at least 60ms (2 * 30ms)
      assert elapsed >= 60
    end

    test "validates base_loss_fn is a function" do
      assert_raise ArgumentError, ~r/base_loss_fn must be a function of arity 2/, fn ->
        Pipeline.compute([], Nx.tensor([1.0]), "not a function")
      end
    end

    test "validates regularizer specs" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      assert_raise ArgumentError, ~r/Each regularizer must be a RegularizerSpec/, fn ->
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn, regularizers: ["not a spec"])
      end
    end

    test "validates no duplicate regularizer names" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{fn: fn _, x -> {Nx.sum(x), %{}} end, weight: 0.1, name: "dup"},
        %RegularizerSpec{fn: fn _, x -> {Nx.mean(x), %{}} end, weight: 0.1, name: "dup"}
      ]

      assert_raise ArgumentError, ~r/Duplicate regularizer names/, fn ->
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn, regularizers: regularizers)
      end
    end

    test "returns error when base loss function fails" do
      base_loss_fn = fn _data, _logprobs -> raise "base loss error" end
      data = []
      logprobs = Nx.tensor([1.0])

      assert {:error, {:pipeline_failed, %RuntimeError{}}} =
               Pipeline.compute(data, logprobs, base_loss_fn)
    end

    test "returns error when regularizer fails" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, _logprobs -> raise "reg error" end,
          weight: 0.1,
          name: "failing"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0])

      assert {:error, {:regularizer_failed, "failing", %RuntimeError{}}} =
               Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)
    end

    test "passes data through to base loss and regularizers" do
      base_loss_fn = fn data, logprobs ->
        {Nx.multiply(Nx.sum(logprobs), length(data)), %{}}
      end

      regularizers = [
        %RegularizerSpec{
          fn: fn data, logprobs ->
            {Nx.multiply(Nx.mean(logprobs), length(data)), %{}}
          end,
          weight: 1.0,
          name: "data_aware"
        }
      ]

      # length = 2
      data = [:a, :b]
      logprobs = Nx.tensor([3.0])

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # base = 3.0 * 2 = 6.0
      # reg = 3.0 * 2 * 1.0 = 6.0
      # total = 12.0
      assert_in_delta output.loss_total, 12.0, 0.001
    end

    test "includes base loss metrics in output" do
      base_loss_fn = fn _data, logprobs ->
        {Nx.sum(logprobs), %{"custom_metric" => 42.0}}
      end

      data = []
      logprobs = Nx.tensor([1.0])

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn)

      assert output.base_loss.custom == %{"custom_metric" => 42.0}
    end
  end
end
