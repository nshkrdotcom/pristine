defmodule Tinkex.Types.TrainingTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.LossFnType
  alias Tinkex.Types.ForwardBackwardInput
  alias Tinkex.Types.ForwardBackwardOutput
  alias Tinkex.Types.ForwardBackwardRequest
  alias Tinkex.Types.ForwardRequest
  alias Tinkex.Types.OptimStepRequest
  alias Tinkex.Types.OptimStepResponse
  alias Tinkex.Types.Datum
  alias Tinkex.Types.AdamParams

  describe "LossFnType" do
    test "values/0 returns all loss function types" do
      values = LossFnType.values()

      assert :cross_entropy in values
      assert :importance_sampling in values
      assert :ppo in values
      assert :cispo in values
      assert :dro in values
      assert :linear_weighted in values
      assert length(values) == 6
    end

    test "parse/1 converts string to atom" do
      assert LossFnType.parse("cross_entropy") == :cross_entropy
      assert LossFnType.parse("importance_sampling") == :importance_sampling
      assert LossFnType.parse("ppo") == :ppo
      assert LossFnType.parse("cispo") == :cispo
      assert LossFnType.parse("dro") == :dro
      assert LossFnType.parse("linear_weighted") == :linear_weighted
    end

    test "parse/1 returns nil for nil input" do
      assert LossFnType.parse(nil) == nil
    end

    test "to_string/1 converts atom to string" do
      assert LossFnType.to_string(:cross_entropy) == "cross_entropy"
      assert LossFnType.to_string(:importance_sampling) == "importance_sampling"
      assert LossFnType.to_string(:ppo) == "ppo"
      assert LossFnType.to_string(:cispo) == "cispo"
      assert LossFnType.to_string(:dro) == "dro"
      assert LossFnType.to_string(:linear_weighted) == "linear_weighted"
    end
  end

  describe "ForwardBackwardInput" do
    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(ForwardBackwardInput, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(ForwardBackwardInput, data: [])
      end
    end

    test "accepts data and loss_fn" do
      datum = %Datum{model_input: %{}, loss_fn_inputs: %{}}

      input = %ForwardBackwardInput{
        data: [datum],
        loss_fn: :cross_entropy
      }

      assert input.data == [datum]
      assert input.loss_fn == :cross_entropy
      assert input.loss_fn_config == nil
    end

    test "accepts optional loss_fn_config" do
      input = %ForwardBackwardInput{
        data: [],
        loss_fn: :ppo,
        loss_fn_config: %{"clip_ratio" => 0.2}
      }

      assert input.loss_fn_config == %{"clip_ratio" => 0.2}
    end

    test "encodes to JSON with atom loss_fn converted to string" do
      input = %ForwardBackwardInput{
        data: [],
        loss_fn: :cross_entropy
      }

      json = Jason.encode!(input)
      decoded = Jason.decode!(json)

      assert decoded["loss_fn"] == "cross_entropy"
      assert decoded["data"] == []
    end
  end

  describe "ForwardBackwardOutput" do
    test "enforces loss_fn_output_type" do
      assert_raise ArgumentError, fn ->
        struct!(ForwardBackwardOutput, [])
      end
    end

    test "has default values" do
      output = %ForwardBackwardOutput{loss_fn_output_type: "cross_entropy"}

      assert output.loss_fn_outputs == []
      assert output.metrics == %{}
    end

    test "from_json/1 parses response" do
      json = %{
        "loss_fn_output_type" => "cross_entropy",
        "loss_fn_outputs" => [%{"logprobs" => -1.5}],
        "metrics" => %{"loss" => 0.5, "grad_norm" => 1.2}
      }

      output = ForwardBackwardOutput.from_json(json)

      assert output.loss_fn_output_type == "cross_entropy"
      assert output.loss_fn_outputs == [%{"logprobs" => -1.5}]
      assert output.metrics == %{"loss" => 0.5, "grad_norm" => 1.2}
    end

    test "loss/1 returns loss from metrics" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        metrics: %{"loss" => 0.42}
      }

      assert ForwardBackwardOutput.loss(output) == 0.42
    end

    test "loss/1 returns nil when no loss in metrics" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        metrics: %{}
      }

      assert ForwardBackwardOutput.loss(output) == nil
    end
  end

  describe "ForwardBackwardRequest" do
    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(ForwardBackwardRequest, [])
      end
    end

    test "accepts forward_backward_input and model_id" do
      input = %ForwardBackwardInput{data: [], loss_fn: :cross_entropy}

      request = %ForwardBackwardRequest{
        forward_backward_input: input,
        model_id: "model_abc"
      }

      assert request.forward_backward_input == input
      assert request.model_id == "model_abc"
      assert request.seq_id == nil
    end

    test "accepts optional seq_id" do
      input = %ForwardBackwardInput{data: [], loss_fn: :cross_entropy}

      request = %ForwardBackwardRequest{
        forward_backward_input: input,
        model_id: "model_abc",
        seq_id: 42
      }

      assert request.seq_id == 42
    end

    test "encodes to JSON" do
      input = %ForwardBackwardInput{data: [], loss_fn: :cross_entropy}

      request = %ForwardBackwardRequest{
        forward_backward_input: input,
        model_id: "model_test",
        seq_id: 1
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model_test"
      assert decoded["seq_id"] == 1
      assert is_map(decoded["forward_backward_input"])
    end
  end

  describe "ForwardRequest" do
    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(ForwardRequest, [])
      end
    end

    test "accepts forward_input and model_id" do
      input = %ForwardBackwardInput{data: [], loss_fn: :cross_entropy}

      request = %ForwardRequest{
        forward_input: input,
        model_id: "model_xyz"
      }

      assert request.forward_input == input
      assert request.model_id == "model_xyz"
      assert request.seq_id == nil
    end

    test "encodes to JSON" do
      input = %ForwardBackwardInput{data: [], loss_fn: :cross_entropy}

      request = %ForwardRequest{
        forward_input: input,
        model_id: "model_forward",
        seq_id: 5
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model_forward"
      assert decoded["seq_id"] == 5
      assert is_map(decoded["forward_input"])
    end
  end

  describe "OptimStepRequest" do
    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(OptimStepRequest, [])
      end
    end

    test "accepts adam_params and model_id" do
      params = %AdamParams{}

      request = %OptimStepRequest{
        adam_params: params,
        model_id: "model_optim"
      }

      assert request.adam_params == params
      assert request.model_id == "model_optim"
      assert request.seq_id == nil
    end

    test "accepts optional seq_id" do
      params = %AdamParams{learning_rate: 0.001}

      request = %OptimStepRequest{
        adam_params: params,
        model_id: "model_optim",
        seq_id: 10
      }

      assert request.seq_id == 10
    end

    test "encodes to JSON" do
      params = %AdamParams{learning_rate: 0.0001}

      request = %OptimStepRequest{
        adam_params: params,
        model_id: "model_step",
        seq_id: 3
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model_step"
      assert decoded["seq_id"] == 3
      assert is_map(decoded["adam_params"])
    end
  end

  describe "OptimStepResponse" do
    test "has nil metrics by default" do
      response = %OptimStepResponse{}
      assert response.metrics == nil
    end

    test "accepts metrics" do
      response = %OptimStepResponse{
        metrics: %{"grad_norm" => 1.5, "lr" => 0.0001}
      }

      assert response.metrics["grad_norm"] == 1.5
    end

    test "from_json/1 parses response" do
      json = %{"metrics" => %{"grad_norm" => 2.0}}
      response = OptimStepResponse.from_json(json)

      assert response.metrics == %{"grad_norm" => 2.0}
    end

    test "from_json/1 handles missing metrics" do
      json = %{}
      response = OptimStepResponse.from_json(json)

      assert response.metrics == nil
    end

    test "success?/1 returns true" do
      response = %OptimStepResponse{}
      assert OptimStepResponse.success?(response) == true
    end
  end
end
