defmodule Tinkex.Types.AdamParamsTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.AdamParams

  describe "struct/0" do
    test "has correct default values (Python SDK parity)" do
      params = %AdamParams{}

      # Note: defaults match Python SDK exactly
      # beta2=0.95 (not 0.999), eps=1e-12 (not 1e-8)
      assert params.learning_rate == 0.0001
      assert params.beta1 == 0.9
      assert params.beta2 == 0.95
      assert params.eps == 1.0e-12
      assert params.weight_decay == 0.0
      assert params.grad_clip_norm == 0.0
    end
  end

  describe "new/1" do
    test "creates params with defaults" do
      assert {:ok, params} = AdamParams.new()

      assert params.learning_rate == 0.0001
      assert params.beta1 == 0.9
      assert params.beta2 == 0.95
    end

    test "accepts valid custom learning_rate" do
      assert {:ok, params} = AdamParams.new(learning_rate: 0.001)
      assert params.learning_rate == 0.001
    end

    test "rejects learning_rate <= 0" do
      assert {:error, message} = AdamParams.new(learning_rate: 0)
      assert message =~ "learning_rate"

      assert {:error, _} = AdamParams.new(learning_rate: -0.001)
    end

    test "accepts valid beta1 values" do
      assert {:ok, params} = AdamParams.new(beta1: 0.0)
      assert params.beta1 == 0.0

      assert {:ok, params} = AdamParams.new(beta1: 0.99)
      assert params.beta1 == 0.99
    end

    test "rejects beta1 >= 1" do
      assert {:error, message} = AdamParams.new(beta1: 1.0)
      assert message =~ "beta1"

      assert {:error, _} = AdamParams.new(beta1: 1.5)
    end

    test "rejects beta1 < 0" do
      assert {:error, message} = AdamParams.new(beta1: -0.1)
      assert message =~ "beta1"
    end

    test "accepts valid beta2 values" do
      assert {:ok, params} = AdamParams.new(beta2: 0.0)
      assert params.beta2 == 0.0

      assert {:ok, params} = AdamParams.new(beta2: 0.999)
      assert params.beta2 == 0.999
    end

    test "rejects beta2 >= 1" do
      assert {:error, message} = AdamParams.new(beta2: 1.0)
      assert message =~ "beta2"
    end

    test "rejects beta2 < 0" do
      assert {:error, _} = AdamParams.new(beta2: -0.5)
    end

    test "accepts valid eps values" do
      assert {:ok, params} = AdamParams.new(eps: 1.0e-8)
      assert params.eps == 1.0e-8
    end

    test "rejects eps <= 0" do
      assert {:error, message} = AdamParams.new(eps: 0)
      assert message =~ "eps"

      assert {:error, _} = AdamParams.new(eps: -1.0e-8)
    end

    test "accepts valid weight_decay values" do
      assert {:ok, params} = AdamParams.new(weight_decay: 0.01)
      assert params.weight_decay == 0.01

      assert {:ok, params} = AdamParams.new(weight_decay: 0.0)
      assert params.weight_decay == 0.0
    end

    test "rejects weight_decay < 0" do
      assert {:error, message} = AdamParams.new(weight_decay: -0.01)
      assert message =~ "weight_decay"
    end

    test "accepts valid grad_clip_norm values" do
      assert {:ok, params} = AdamParams.new(grad_clip_norm: 1.0)
      assert params.grad_clip_norm == 1.0

      assert {:ok, params} = AdamParams.new(grad_clip_norm: 0.0)
      assert params.grad_clip_norm == 0.0
    end

    test "rejects grad_clip_norm < 0" do
      assert {:error, message} = AdamParams.new(grad_clip_norm: -0.5)
      assert message =~ "grad_clip_norm"
    end

    test "accepts multiple custom values" do
      assert {:ok, params} =
               AdamParams.new(
                 learning_rate: 0.01,
                 beta1: 0.85,
                 beta2: 0.999,
                 eps: 1.0e-8,
                 weight_decay: 0.1,
                 grad_clip_norm: 1.0
               )

      assert params.learning_rate == 0.01
      assert params.beta1 == 0.85
      assert params.beta2 == 0.999
      assert params.eps == 1.0e-8
      assert params.weight_decay == 0.1
      assert params.grad_clip_norm == 1.0
    end

    test "returns first validation error when multiple invalid" do
      # When multiple validations fail, one error is returned
      assert {:error, _message} = AdamParams.new(learning_rate: -1, beta1: 2.0)
    end
  end

  describe "JSON encoding" do
    test "encodes all fields correctly" do
      {:ok, params} =
        AdamParams.new(
          learning_rate: 0.001,
          beta1: 0.85,
          beta2: 0.99,
          eps: 1.0e-10,
          weight_decay: 0.05,
          grad_clip_norm: 2.0
        )

      json = Jason.encode!(params)
      decoded = Jason.decode!(json)

      assert decoded["learning_rate"] == 0.001
      assert decoded["beta1"] == 0.85
      assert decoded["beta2"] == 0.99
      assert decoded["eps"] == 1.0e-10
      assert decoded["weight_decay"] == 0.05
      assert decoded["grad_clip_norm"] == 2.0
    end

    test "encodes with all defaults" do
      {:ok, params} = AdamParams.new()
      json = Jason.encode!(params)
      decoded = Jason.decode!(json)

      assert decoded["learning_rate"] == 0.0001
      assert decoded["beta1"] == 0.9
      assert decoded["beta2"] == 0.95
      assert decoded["eps"] == 1.0e-12
      assert decoded["weight_decay"] == 0.0
      assert decoded["grad_clip_norm"] == 0.0
    end
  end
end
