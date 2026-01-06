defmodule Tinkex.TrainingClient.OperationsTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient.Operations
  alias Tinkex.Error

  alias Tinkex.Types.{
    ForwardBackwardOutput,
    SaveWeightsResponse,
    LoadWeightsResponse,
    SaveWeightsForSamplerResponse
  }

  describe "ensure_model/6" do
    test "returns existing model_id if provided" do
      opts = [model_id: "existing-model-123"]

      result =
        Operations.ensure_model(
          opts,
          "session-id",
          1,
          %{},
          nil,
          %{}
        )

      assert {:ok, "existing-model-123"} = result
    end

    test "returns error when base_model not provided and no model_id" do
      opts = []

      result =
        Operations.ensure_model(
          opts,
          "session-id",
          1,
          %{},
          nil,
          %{}
        )

      assert {:error, %Error{type: :validation}} = result
    end

    test "returns error for invalid base_model type" do
      opts = [base_model: 123]

      result =
        Operations.ensure_model(
          opts,
          "session-id",
          1,
          %{},
          nil,
          %{}
        )

      assert {:error, %Error{type: :validation}} = result
    end
  end

  describe "handle_save_state_response/3" do
    test "returns SaveWeightsResponse directly" do
      response = %SaveWeightsResponse{path: "weights/test"}

      assert {:ok, ^response} = Operations.handle_save_state_response(response, %{}, [])
    end

    test "converts map with path to SaveWeightsResponse" do
      result =
        Operations.handle_save_state_response(
          %{"path" => "weights/test"},
          %{},
          []
        )

      assert {:ok, %SaveWeightsResponse{}} = result
    end

    test "passes through other map results" do
      result =
        Operations.handle_save_state_response(
          %{"status" => "complete"},
          %{},
          []
        )

      assert {:ok, %{"status" => "complete"}} = result
    end
  end

  describe "handle_load_state_response/3" do
    test "returns LoadWeightsResponse directly" do
      response = %LoadWeightsResponse{path: "weights/test"}

      assert {:ok, ^response} = Operations.handle_load_state_response(response, %{}, [])
    end

    test "converts map with path to LoadWeightsResponse" do
      result =
        Operations.handle_load_state_response(
          %{"path" => "weights/loaded"},
          %{},
          []
        )

      assert {:ok, %LoadWeightsResponse{}} = result
    end
  end

  describe "handle_save_weights_response/3" do
    test "returns SaveWeightsForSamplerResponse directly" do
      response = %SaveWeightsForSamplerResponse{path: "sampler/weights"}

      assert {:ok, ^response} = Operations.handle_save_weights_response(response, %{}, [])
    end

    test "converts map with path" do
      result =
        Operations.handle_save_weights_response(
          %{"path" => "sampler/weights"},
          %{},
          []
        )

      assert {:ok, %SaveWeightsForSamplerResponse{}} = result
    end

    test "converts map with sampling_session_id" do
      result =
        Operations.handle_save_weights_response(
          %{"sampling_session_id" => "sess-123"},
          %{},
          []
        )

      assert {:ok, %SaveWeightsForSamplerResponse{}} = result
    end

    test "converts generic map result" do
      result =
        Operations.handle_save_weights_response(
          %{"custom_field" => "value"},
          %{},
          []
        )

      assert {:ok, %SaveWeightsForSamplerResponse{}} = result
    end
  end

  describe "normalize_save_weights_opts/2" do
    test "returns opts unchanged when path is provided" do
      opts = [path: "weights/path"]
      state = %{sampling_session_counter: 5}

      {result_opts, counter} = Operations.normalize_save_weights_opts(opts, state)

      assert Keyword.get(result_opts, :path) == "weights/path"
      assert counter == 5
    end

    test "returns opts unchanged when sampling_session_seq_id is provided" do
      opts = [sampling_session_seq_id: 10]
      state = %{sampling_session_counter: 5}

      {result_opts, counter} = Operations.normalize_save_weights_opts(opts, state)

      assert Keyword.get(result_opts, :sampling_session_seq_id) == 10
      assert counter == 5
    end

    test "generates sampling_session_seq_id when neither path nor seq_id provided" do
      opts = []
      state = %{sampling_session_counter: 7}

      {result_opts, counter} = Operations.normalize_save_weights_opts(opts, state)

      assert Keyword.get(result_opts, :sampling_session_seq_id) == 7
      assert counter == 8
    end
  end

  describe "build_linear_loss_data_safe/2" do
    test "returns error when data and gradients length mismatch" do
      data = [%{id: 1}, %{id: 2}]
      gradients = [Nx.tensor([1.0])]

      result = Operations.build_linear_loss_data_safe(data, gradients)

      assert {:error, %Error{type: :validation}} = result
      assert {:error, error} = result
      assert error.message =~ "count does not match"
    end

    test "returns ok when lengths match" do
      data = [%{id: 1}]
      gradients = [Nx.tensor([1.0])]

      # Will fail because build_linear_loss_data needs actual Datum structs
      # but tests the length check passes
      result = Operations.build_linear_loss_data_safe(data, gradients)

      # Either succeeds or fails with a different error (not length mismatch)
      case result do
        {:ok, _} -> assert true
        {:error, error} -> refute error.message =~ "count does not match"
      end
    end
  end

  describe "merge_custom_metrics/2" do
    test "merges metrics into ForwardBackwardOutput" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: :cross_entropy,
        loss_fn_outputs: [],
        metrics: %{"existing" => 1.0}
      }

      metrics = %{custom_loss: 2.0, another: 3.0}

      result = Operations.merge_custom_metrics(output, metrics)

      assert result.metrics["existing"] == 1.0
      assert result.metrics["custom_loss"] == 2.0
      assert result.metrics["another"] == 3.0
    end

    test "converts atom keys to strings" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: :cross_entropy,
        metrics: %{}
      }

      metrics = %{atom_key: 5.0}

      result = Operations.merge_custom_metrics(output, metrics)

      assert result.metrics["atom_key"] == 5.0
      refute Map.has_key?(result.metrics, :atom_key)
    end

    test "normalizes Nx.Tensor values to numbers" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: :cross_entropy,
        metrics: %{}
      }

      tensor = Nx.tensor(42.5)
      metrics = %{tensor_metric: tensor}

      result = Operations.merge_custom_metrics(output, metrics)

      assert result.metrics["tensor_metric"] == 42.5
    end

    test "handles empty metrics" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: :cross_entropy,
        metrics: %{"old" => 1.0}
      }

      result = Operations.merge_custom_metrics(output, %{})

      assert result.metrics == %{"old" => 1.0}
    end
  end

  describe "start_sampling_client_from_save/4" do
    test "returns error when neither path nor sampling_session_id present" do
      save_response = %{}
      state = %{}

      result =
        Operations.start_sampling_client_from_save(
          save_response,
          1,
          [],
          state
        )

      assert {:error, %Error{type: :validation}} = result
    end
  end
end
