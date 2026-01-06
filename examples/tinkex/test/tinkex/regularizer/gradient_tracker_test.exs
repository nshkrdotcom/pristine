defmodule Tinkex.Regularizer.GradientTrackerTest do
  @moduledoc """
  Tests for gradient norm computation using Nx automatic differentiation.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.GradientTracker
  alias Tinkex.Types.RegularizerSpec

  describe "compute_grad_norm/2" do
    test "computes gradient norm for simple sum function" do
      # For f(x) = sum(x), grad = [1, 1, 1], ||grad|| = sqrt(3)
      loss_fn = fn x -> Nx.sum(x) end
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

      assert_in_delta norm, :math.sqrt(3), 0.001
    end

    test "computes gradient norm for squared sum" do
      # For f(x) = sum(x^2), grad = 2*x
      # x = [1, 2, 3], grad = [2, 4, 6], ||grad|| = sqrt(4+16+36) = sqrt(56)
      loss_fn = fn x -> Nx.sum(Nx.pow(x, 2)) end
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

      expected = :math.sqrt(4 + 16 + 36)
      assert_in_delta norm, expected, 0.001
    end

    test "computes gradient norm for 2D tensor" do
      # f(x) = sum(x), grad = all ones, ||grad|| = sqrt(6)
      loss_fn = fn x -> Nx.sum(x) end
      logprobs = Nx.tensor([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])

      norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

      assert_in_delta norm, :math.sqrt(6), 0.001
    end

    test "computes gradient norm for mean function" do
      # f(x) = mean(x), grad = 1/n for each element
      # x = [1, 2, 3], grad = [1/3, 1/3, 1/3], ||grad|| = sqrt(3 * (1/9)) = sqrt(1/3)
      loss_fn = fn x -> Nx.mean(x) end
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

      expected = :math.sqrt(3 * (1 / 9))
      assert_in_delta norm, expected, 0.001
    end

    test "returns float" do
      loss_fn = fn x -> Nx.sum(x) end
      logprobs = Nx.tensor([1.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

      assert is_float(norm)
    end
  end

  describe "grad_norm_for_regularizer/3" do
    test "computes gradient norm for regularizer spec" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
        weight: 0.1,
        name: "test_reg"
      }

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      assert_in_delta norm, :math.sqrt(3), 0.001
    end

    test "handles regularizer returning non-scalar loss" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs -> {logprobs, %{}} end,
        weight: 0.1,
        name: "vector_loss"
      }

      data = []
      logprobs = Nx.tensor([1.0, 2.0])

      # Should sum the loss to make it scalar
      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      # For sum(x), ||grad|| = sqrt(2)
      assert_in_delta norm, :math.sqrt(2), 0.001
    end

    test "returns 0.0 for non-differentiable operations" do
      spec = %RegularizerSpec{
        fn: fn _data, _logprobs ->
          # A function that might cause differentiation issues
          raise "non-differentiable"
        end,
        weight: 0.1,
        name: "bad_reg"
      }

      data = []
      logprobs = Nx.tensor([1.0])

      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      assert norm == 0.0
    end

    test "passes data through to regularizer function" do
      spec = %RegularizerSpec{
        fn: fn data, logprobs ->
          # Data influences the loss
          scale = length(data)
          {Nx.sum(Nx.multiply(logprobs, scale)), %{}}
        end,
        weight: 0.1,
        name: "data_aware"
      }

      # length = 3
      data = [:a, :b, :c]
      logprobs = Nx.tensor([1.0, 2.0])

      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      # grad = 3 * [1, 1] = [3, 3], ||grad|| = sqrt(18)
      assert_in_delta norm, :math.sqrt(18), 0.001
    end
  end

  describe "total_grad_norm/4" do
    test "computes gradient norm for base loss only" do
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end
      regularizers = []
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      assert_in_delta norm, :math.sqrt(3), 0.001
    end

    test "computes gradient norm for base loss plus regularizers" do
      # total = base + 0.5 * reg
      # base = sum(x), grad_base = [1, 1]
      # reg = sum(x^2), grad_reg = [2, 4] for x = [1, 2]
      # total_grad = [1, 1] + 0.5 * [2, 4] = [2, 3]
      # ||total_grad|| = sqrt(4 + 9) = sqrt(13)
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(Nx.pow(logprobs, 2)), %{}} end,
          weight: 0.5,
          name: "squared"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      assert_in_delta norm, :math.sqrt(13), 0.001
    end

    test "handles multiple regularizers" do
      # total = base + w1*reg1 + w2*reg2
      base_loss_fn = fn _data, logprobs -> {Nx.sum(logprobs), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(Nx.pow(logprobs, 2)), %{}} end,
          weight: 0.1,
          name: "l2"
        },
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(Nx.abs(logprobs)), %{}} end,
          weight: 0.2,
          name: "l1"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      # Should return a positive float
      assert is_float(norm)
      assert norm > 0
    end

    test "returns 0.0 on failure" do
      base_loss_fn = fn _data, _logprobs -> raise "error" end
      regularizers = []
      data = []
      logprobs = Nx.tensor([1.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      assert norm == 0.0
    end
  end
end
