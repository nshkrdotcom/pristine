defmodule Tinkex.Types.SessionModelTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    ListSessionsResponse,
    GetSessionResponse,
    ModelData,
    UnloadModelRequest,
    UnloadModelResponse,
    GetSamplerResponse
  }

  describe "ListSessionsResponse" do
    test "from_map/1 parses with string keys" do
      map = %{"sessions" => ["session-1", "session-2", "session-3"]}
      response = ListSessionsResponse.from_map(map)

      assert response.sessions == ["session-1", "session-2", "session-3"]
    end

    test "from_map/1 parses with atom keys" do
      map = %{sessions: ["session-1", "session-2"]}
      response = ListSessionsResponse.from_map(map)

      assert response.sessions == ["session-1", "session-2"]
    end

    test "from_map/1 defaults to empty list" do
      response = ListSessionsResponse.from_map(%{})
      assert response.sessions == []
    end
  end

  describe "GetSessionResponse" do
    test "from_map/1 parses with string keys" do
      map = %{
        "training_run_ids" => ["run-1", "run-2"],
        "sampler_ids" => ["sampler-1"]
      }

      response = GetSessionResponse.from_map(map)

      assert response.training_run_ids == ["run-1", "run-2"]
      assert response.sampler_ids == ["sampler-1"]
    end

    test "from_map/1 parses with atom keys" do
      map = %{
        training_run_ids: ["run-1"],
        sampler_ids: ["sampler-1", "sampler-2"]
      }

      response = GetSessionResponse.from_map(map)

      assert response.training_run_ids == ["run-1"]
      assert response.sampler_ids == ["sampler-1", "sampler-2"]
    end

    test "from_map/1 defaults to empty lists" do
      response = GetSessionResponse.from_map(%{})

      assert response.training_run_ids == []
      assert response.sampler_ids == []
    end
  end

  describe "ModelData" do
    test "from_json/1 parses with string keys" do
      json = %{
        "arch" => "transformer",
        "model_name" => "llama-3",
        "tokenizer_id" => "llama-tokenizer"
      }

      model_data = ModelData.from_json(json)

      assert model_data.arch == "transformer"
      assert model_data.model_name == "llama-3"
      assert model_data.tokenizer_id == "llama-tokenizer"
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        arch: "transformer",
        model_name: "llama-3",
        tokenizer_id: "llama-tokenizer"
      }

      model_data = ModelData.from_json(json)

      assert model_data.arch == "transformer"
      assert model_data.model_name == "llama-3"
      assert model_data.tokenizer_id == "llama-tokenizer"
    end

    test "from_json/1 handles missing fields" do
      model_data = ModelData.from_json(%{})

      assert model_data.arch == nil
      assert model_data.model_name == nil
      assert model_data.tokenizer_id == nil
    end
  end

  describe "UnloadModelRequest" do
    test "creates struct with required model_id" do
      request = %UnloadModelRequest{model_id: "model-123"}

      assert request.model_id == "model-123"
      assert request.type == "unload_model"
    end

    test "new/1 creates request" do
      request = UnloadModelRequest.new("model-123")

      assert request.model_id == "model-123"
      assert request.type == "unload_model"
    end

    test "encodes to JSON" do
      request = UnloadModelRequest.new("model-123")
      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model-123"
      assert decoded["type"] == "unload_model"
    end

    test "enforces model_id" do
      assert_raise ArgumentError, fn ->
        struct!(UnloadModelRequest, [])
      end
    end
  end

  describe "UnloadModelResponse" do
    test "from_json/1 parses with string keys" do
      json = %{"model_id" => "model-123", "type" => "unload_model"}
      response = UnloadModelResponse.from_json(json)

      assert response.model_id == "model-123"
      assert response.type == "unload_model"
    end

    test "from_json/1 parses with atom keys" do
      json = %{model_id: "model-123", type: "unload_model"}
      response = UnloadModelResponse.from_json(json)

      assert response.model_id == "model-123"
      assert response.type == "unload_model"
    end
  end

  describe "GetSamplerResponse" do
    test "from_json/1 parses with string keys" do
      json = %{
        "sampler_id" => "sampler-123",
        "base_model" => "llama-3",
        "model_path" => "tinker://run-123/sampler_weights/ckpt-001"
      }

      response = GetSamplerResponse.from_json(json)

      assert response.sampler_id == "sampler-123"
      assert response.base_model == "llama-3"
      assert response.model_path == "tinker://run-123/sampler_weights/ckpt-001"
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        sampler_id: "sampler-123",
        base_model: "llama-3",
        model_path: "tinker://run-123/sampler_weights/ckpt-001"
      }

      response = GetSamplerResponse.from_json(json)

      assert response.sampler_id == "sampler-123"
      assert response.base_model == "llama-3"
      assert response.model_path == "tinker://run-123/sampler_weights/ckpt-001"
    end

    test "from_json/1 handles missing model_path" do
      json = %{"sampler_id" => "sampler-123", "base_model" => "llama-3"}
      response = GetSamplerResponse.from_json(json)

      assert response.sampler_id == "sampler-123"
      assert response.base_model == "llama-3"
      assert response.model_path == nil
    end

    test "encodes to JSON with model_path" do
      response = %GetSamplerResponse{
        sampler_id: "sampler-123",
        base_model: "llama-3",
        model_path: "tinker://path"
      }

      json = Jason.encode!(response)
      decoded = Jason.decode!(json)

      assert decoded["sampler_id"] == "sampler-123"
      assert decoded["base_model"] == "llama-3"
      assert decoded["model_path"] == "tinker://path"
    end

    test "encodes to JSON without model_path" do
      response = %GetSamplerResponse{
        sampler_id: "sampler-123",
        base_model: "llama-3",
        model_path: nil
      }

      json = Jason.encode!(response)
      decoded = Jason.decode!(json)

      assert decoded["sampler_id"] == "sampler-123"
      assert decoded["base_model"] == "llama-3"
      refute Map.has_key?(decoded, "model_path")
    end
  end
end
