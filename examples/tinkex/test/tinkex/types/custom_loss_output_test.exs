defmodule Tinkex.Types.CustomLossOutputTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.CustomLossOutput

  describe "build/4" do
    test "builds with base loss only" do
      output = CustomLossOutput.build(1.5, %{}, [])

      assert output.loss_total == 1.5
      assert output.base_loss.value == 1.5
      assert output.base_loss.custom == %{}
      assert output.regularizer_total == 0
      assert output.regularizers == %{}
    end

    test "builds with base loss and metrics" do
      metrics = %{"accuracy" => 0.95, "perplexity" => 10.5}
      output = CustomLossOutput.build(1.5, metrics, [])

      assert output.base_loss.custom == metrics
    end

    test "builds with regularizers" do
      regularizers = [
        %{name: "l2", contribution: 0.1, weight: 0.01},
        %{name: "entropy", contribution: 0.05, weight: 0.005}
      ]

      output = CustomLossOutput.build(1.5, %{}, regularizers)

      assert_in_delta output.loss_total, 1.65, 0.0001
      assert_in_delta output.regularizer_total, 0.15, 0.0001
      assert map_size(output.regularizers) == 2
      assert output.regularizers["l2"].contribution == 0.1
      assert output.regularizers["entropy"].contribution == 0.05
    end

    test "builds with gradient norms" do
      output =
        CustomLossOutput.build(1.5, %{}, [],
          base_grad_norm: 0.5,
          total_grad_norm: 0.6
        )

      assert output.base_loss.grad_norm == 0.5
      assert output.total_grad_norm == 0.6
    end

    test "handles nil base_loss_metrics" do
      output = CustomLossOutput.build(1.5, nil, [])

      assert output.base_loss.custom == %{}
    end
  end

  describe "loss/1" do
    test "returns total loss" do
      output = %CustomLossOutput{loss_total: 2.5}
      assert CustomLossOutput.loss(output) == 2.5
    end

    test "returns loss from built output" do
      regularizers = [%{name: "l2", contribution: 0.5}]
      output = CustomLossOutput.build(1.0, %{}, regularizers)

      assert CustomLossOutput.loss(output) == 1.5
    end
  end

  describe "Jason.Encoder" do
    test "encodes full output" do
      regularizers = [%{name: "l2", contribution: 0.1, weight: 0.01}]

      output =
        CustomLossOutput.build(1.5, %{"metric" => 1.0}, regularizers, total_grad_norm: 0.5)

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["loss_total"] == 1.6
      assert decoded["regularizer_total"] == 0.1
      assert decoded["base_loss"]["value"] == 1.5
      assert decoded["total_grad_norm"] == 0.5
      assert decoded["regularizers"]["l2"]["contribution"] == 0.1
    end

    test "encodes without optional fields" do
      output = %CustomLossOutput{
        loss_total: 1.5,
        regularizer_total: 0,
        regularizers: %{},
        base_loss: nil,
        total_grad_norm: nil
      }

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["loss_total"] == 1.5
      refute Map.has_key?(decoded, "base_loss")
      refute Map.has_key?(decoded, "total_grad_norm")
    end
  end
end
