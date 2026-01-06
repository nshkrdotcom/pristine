defmodule Tinkex.Types.WeightTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    SaveWeightsRequest,
    SaveWeightsResponse,
    SaveWeightsForSamplerRequest,
    SaveWeightsForSamplerResponse,
    LoadWeightsRequest,
    LoadWeightsResponse
  }

  describe "SaveWeightsRequest" do
    test "creates struct with required model_id" do
      request = %SaveWeightsRequest{model_id: "model-123"}
      assert request.model_id == "model-123"
      assert request.type == "save_weights"
      assert request.path == nil
      assert request.seq_id == nil
    end

    test "creates struct with all fields" do
      request = %SaveWeightsRequest{
        model_id: "model-123",
        path: "tinker://run-123/weights/ckpt-001",
        seq_id: 42
      }

      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/weights/ckpt-001"
      assert request.seq_id == 42
      assert request.type == "save_weights"
    end

    test "encodes to JSON" do
      request = %SaveWeightsRequest{
        model_id: "model-123",
        path: "tinker://run-123/weights/ckpt-001",
        seq_id: 1
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model-123"
      assert decoded["path"] == "tinker://run-123/weights/ckpt-001"
      assert decoded["seq_id"] == 1
      assert decoded["type"] == "save_weights"
    end

    test "enforces model_id" do
      assert_raise ArgumentError, fn ->
        struct!(SaveWeightsRequest, [])
      end
    end
  end

  describe "SaveWeightsResponse" do
    test "creates struct with required path" do
      response = %SaveWeightsResponse{path: "tinker://run-123/weights/ckpt-001"}
      assert response.path == "tinker://run-123/weights/ckpt-001"
      assert response.type == "save_weights"
    end

    test "parses from JSON with string keys" do
      json = %{
        "path" => "tinker://run-123/weights/ckpt-001",
        "type" => "save_weights"
      }

      response = SaveWeightsResponse.from_json(json)
      assert response.path == "tinker://run-123/weights/ckpt-001"
      assert response.type == "save_weights"
    end

    test "parses from JSON with atom keys" do
      json = %{
        path: "tinker://run-123/weights/ckpt-001",
        type: "save_weights"
      }

      response = SaveWeightsResponse.from_json(json)
      assert response.path == "tinker://run-123/weights/ckpt-001"
      assert response.type == "save_weights"
    end

    test "defaults type when not present" do
      json = %{"path" => "tinker://run-123/weights/ckpt-001"}
      response = SaveWeightsResponse.from_json(json)
      assert response.type == "save_weights"
    end

    test "enforces path" do
      assert_raise ArgumentError, fn ->
        struct!(SaveWeightsResponse, [])
      end
    end
  end

  describe "SaveWeightsForSamplerRequest" do
    test "creates struct with required model_id" do
      request = %SaveWeightsForSamplerRequest{model_id: "model-123"}
      assert request.model_id == "model-123"
      assert request.type == "save_weights_for_sampler"
      assert request.path == nil
      assert request.sampling_session_seq_id == nil
      assert request.seq_id == nil
    end

    test "creates struct with all fields" do
      request = %SaveWeightsForSamplerRequest{
        model_id: "model-123",
        path: "tinker://run-123/sampler_weights/ckpt-001",
        sampling_session_seq_id: 10,
        seq_id: 42
      }

      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/sampler_weights/ckpt-001"
      assert request.sampling_session_seq_id == 10
      assert request.seq_id == 42
      assert request.type == "save_weights_for_sampler"
    end

    test "encodes to JSON" do
      request = %SaveWeightsForSamplerRequest{
        model_id: "model-123",
        path: "tinker://run-123/sampler_weights/ckpt-001",
        sampling_session_seq_id: 10,
        seq_id: 1
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model-123"
      assert decoded["path"] == "tinker://run-123/sampler_weights/ckpt-001"
      assert decoded["sampling_session_seq_id"] == 10
      assert decoded["seq_id"] == 1
      assert decoded["type"] == "save_weights_for_sampler"
    end
  end

  describe "SaveWeightsForSamplerResponse" do
    test "creates struct with defaults" do
      response = %SaveWeightsForSamplerResponse{}
      assert response.path == nil
      assert response.sampling_session_id == nil
      assert response.type == "save_weights_for_sampler"
    end

    test "parses from JSON with string keys" do
      json = %{
        "path" => "tinker://run-123/sampler_weights/ckpt-001",
        "sampling_session_id" => "session-456",
        "type" => "save_weights_for_sampler"
      }

      response = SaveWeightsForSamplerResponse.from_json(json)
      assert response.path == "tinker://run-123/sampler_weights/ckpt-001"
      assert response.sampling_session_id == "session-456"
      assert response.type == "save_weights_for_sampler"
    end

    test "parses from JSON with atom keys" do
      json = %{
        path: "tinker://run-123/sampler_weights/ckpt-001",
        sampling_session_id: "session-456",
        type: "save_weights_for_sampler"
      }

      response = SaveWeightsForSamplerResponse.from_json(json)
      assert response.path == "tinker://run-123/sampler_weights/ckpt-001"
      assert response.sampling_session_id == "session-456"
      assert response.type == "save_weights_for_sampler"
    end

    test "handles missing fields" do
      json = %{}
      response = SaveWeightsForSamplerResponse.from_json(json)
      assert response.path == nil
      assert response.sampling_session_id == nil
      assert response.type == "save_weights_for_sampler"
    end
  end

  describe "LoadWeightsRequest" do
    test "creates struct with required fields" do
      request = %LoadWeightsRequest{
        model_id: "model-123",
        path: "tinker://run-123/weights/ckpt-001"
      }

      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/weights/ckpt-001"
      assert request.optimizer == false
      assert request.type == "load_weights"
      assert request.seq_id == nil
    end

    test "creates struct with all fields" do
      request = %LoadWeightsRequest{
        model_id: "model-123",
        path: "tinker://run-123/weights/ckpt-001",
        seq_id: 42,
        optimizer: true
      }

      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/weights/ckpt-001"
      assert request.seq_id == 42
      assert request.optimizer == true
      assert request.type == "load_weights"
    end

    test "new/2 creates request with defaults" do
      request = LoadWeightsRequest.new("model-123", "tinker://run-123/weights/ckpt-001")
      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/weights/ckpt-001"
      assert request.optimizer == false
      assert request.seq_id == nil
      assert request.type == "load_weights"
    end

    test "new/3 creates request with options" do
      request =
        LoadWeightsRequest.new("model-123", "tinker://run-123/weights/ckpt-001",
          optimizer: true,
          seq_id: 10
        )

      assert request.model_id == "model-123"
      assert request.path == "tinker://run-123/weights/ckpt-001"
      assert request.optimizer == true
      assert request.seq_id == 10
      assert request.type == "load_weights"
    end

    test "encodes to JSON" do
      request =
        LoadWeightsRequest.new("model-123", "tinker://run-123/weights/ckpt-001",
          optimizer: true,
          seq_id: 1
        )

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model-123"
      assert decoded["path"] == "tinker://run-123/weights/ckpt-001"
      assert decoded["optimizer"] == true
      assert decoded["seq_id"] == 1
      assert decoded["type"] == "load_weights"
    end

    test "enforces model_id and path" do
      assert_raise ArgumentError, fn ->
        struct!(LoadWeightsRequest, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(LoadWeightsRequest, model_id: "model-123")
      end
    end
  end

  describe "LoadWeightsResponse" do
    test "creates struct with defaults" do
      response = %LoadWeightsResponse{}
      assert response.path == nil
      assert response.type == "load_weights"
    end

    test "parses from JSON with string keys" do
      json = %{
        "path" => "tinker://run-123/weights/ckpt-001",
        "type" => "load_weights"
      }

      response = LoadWeightsResponse.from_json(json)
      assert response.path == "tinker://run-123/weights/ckpt-001"
      assert response.type == "load_weights"
    end

    test "parses from JSON with atom keys" do
      json = %{
        path: "tinker://run-123/weights/ckpt-001",
        type: "load_weights"
      }

      response = LoadWeightsResponse.from_json(json)
      assert response.path == "tinker://run-123/weights/ckpt-001"
      assert response.type == "load_weights"
    end

    test "defaults type when not present (string keys)" do
      json = %{"path" => "tinker://run-123/weights/ckpt-001"}
      response = LoadWeightsResponse.from_json(json)
      assert response.type == "load_weights"
    end

    test "handles missing path with atom keys" do
      json = %{}
      response = LoadWeightsResponse.from_json(json)
      assert response.path == nil
      assert response.type == "load_weights"
    end
  end
end
