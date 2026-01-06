defmodule Tinkex.Types.ModelTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.CreateModelRequest
  alias Tinkex.Types.CreateModelResponse
  alias Tinkex.Types.GetInfoRequest
  alias Tinkex.Types.GetInfoResponse
  alias Tinkex.Types.LoraConfig

  describe "CreateModelRequest" do
    test "has correct default type" do
      request = %CreateModelRequest{
        session_id: "sess_abc",
        model_seq_id: 1,
        base_model: "kimi-k2"
      }

      assert request.type == "create_model"
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(CreateModelRequest, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(CreateModelRequest, session_id: "sess", model_seq_id: 1)
      end
    end

    test "accepts required fields" do
      request = %CreateModelRequest{
        session_id: "sess_xyz",
        model_seq_id: 42,
        base_model: "llama-3"
      }

      assert request.session_id == "sess_xyz"
      assert request.model_seq_id == 42
      assert request.base_model == "llama-3"
    end

    test "has default lora_config" do
      request = %CreateModelRequest{
        session_id: "sess_abc",
        model_seq_id: 1,
        base_model: "kimi-k2"
      }

      assert request.lora_config == %LoraConfig{}
      assert request.lora_config.rank == 32
    end

    test "accepts custom lora_config" do
      custom_lora = %LoraConfig{rank: 64, train_mlp: false}

      request = %CreateModelRequest{
        session_id: "sess_abc",
        model_seq_id: 1,
        base_model: "kimi-k2",
        lora_config: custom_lora
      }

      assert request.lora_config.rank == 64
      assert request.lora_config.train_mlp == false
    end

    test "accepts optional user_metadata" do
      request = %CreateModelRequest{
        session_id: "sess_abc",
        model_seq_id: 1,
        base_model: "kimi-k2",
        user_metadata: %{"experiment" => "v1"}
      }

      assert request.user_metadata == %{"experiment" => "v1"}
    end

    test "user_metadata defaults to nil" do
      request = %CreateModelRequest{
        session_id: "sess_abc",
        model_seq_id: 1,
        base_model: "kimi-k2"
      }

      assert request.user_metadata == nil
    end

    test "encodes to JSON correctly" do
      request = %CreateModelRequest{
        session_id: "sess_test",
        model_seq_id: 5,
        base_model: "llama-3",
        user_metadata: %{"key" => "value"}
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["session_id"] == "sess_test"
      assert decoded["model_seq_id"] == 5
      assert decoded["base_model"] == "llama-3"
      assert decoded["type"] == "create_model"
      assert decoded["user_metadata"] == %{"key" => "value"}
      assert is_map(decoded["lora_config"])
    end
  end

  describe "CreateModelResponse" do
    test "enforces model_id" do
      assert_raise ArgumentError, fn ->
        struct!(CreateModelResponse, [])
      end
    end

    test "accepts model_id" do
      response = %CreateModelResponse{model_id: "model_abc123"}
      assert response.model_id == "model_abc123"
    end

    test "from_json/1 parses string-keyed map" do
      json = %{"model_id" => "model_parsed"}
      response = CreateModelResponse.from_json(json)

      assert response.model_id == "model_parsed"
    end
  end

  describe "GetInfoRequest" do
    test "has correct default type" do
      request = %GetInfoRequest{model_id: "model_abc"}
      assert request.type == "get_info"
    end

    test "enforces model_id" do
      assert_raise ArgumentError, fn ->
        struct!(GetInfoRequest, [])
      end
    end

    test "new/1 creates request with model_id" do
      request = GetInfoRequest.new("model_test123")

      assert request.model_id == "model_test123"
      assert request.type == "get_info"
    end

    test "encodes to JSON correctly" do
      request = GetInfoRequest.new("model_xyz")
      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["model_id"] == "model_xyz"
      assert decoded["type"] == "get_info"
    end
  end

  describe "GetInfoResponse" do
    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(GetInfoResponse, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(GetInfoResponse, model_id: "model_abc")
      end
    end

    test "accepts required fields" do
      model_data = %{arch: "transformer", model_name: "kimi-k2", tokenizer_id: "kimi"}

      response = %GetInfoResponse{
        model_id: "model_abc",
        model_data: model_data
      }

      assert response.model_id == "model_abc"
      assert response.model_data == model_data
    end

    test "optional fields default to nil" do
      response = %GetInfoResponse{
        model_id: "model_abc",
        model_data: %{}
      }

      assert response.is_lora == nil
      assert response.lora_rank == nil
      assert response.model_name == nil
      assert response.type == nil
    end

    test "accepts all optional fields" do
      response = %GetInfoResponse{
        model_id: "model_abc",
        model_data: %{},
        is_lora: true,
        lora_rank: 32,
        model_name: "my-fine-tuned",
        type: "get_info_response"
      }

      assert response.is_lora == true
      assert response.lora_rank == 32
      assert response.model_name == "my-fine-tuned"
    end

    test "from_json/1 parses string-keyed map" do
      json = %{
        "model_id" => "model_parsed",
        "model_data" => %{"arch" => "transformer"},
        "is_lora" => true,
        "lora_rank" => 64,
        "model_name" => "custom-model"
      }

      response = GetInfoResponse.from_json(json)

      assert response.model_id == "model_parsed"
      assert response.model_data == %{"arch" => "transformer"}
      assert response.is_lora == true
      assert response.lora_rank == 64
      assert response.model_name == "custom-model"
    end

    test "from_json/1 parses atom-keyed map" do
      json = %{
        model_id: "model_atom",
        model_data: %{arch: "transformer"},
        is_lora: false
      }

      response = GetInfoResponse.from_json(json)

      assert response.model_id == "model_atom"
      assert response.is_lora == false
    end

    test "from_json/1 handles missing optional fields" do
      json = %{
        "model_id" => "model_minimal",
        "model_data" => %{}
      }

      response = GetInfoResponse.from_json(json)

      assert response.model_id == "model_minimal"
      assert response.is_lora == nil
      assert response.lora_rank == nil
    end
  end
end
