defmodule Tinkex.Types.ServerTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{HealthResponse, SupportedModel, GetServerCapabilitiesResponse}

  describe "HealthResponse" do
    test "from_json/1 parses with string keys" do
      json = %{"status" => "healthy"}
      response = HealthResponse.from_json(json)
      assert response.status == "healthy"
    end

    test "from_json/1 parses with atom keys" do
      json = %{status: "healthy"}
      response = HealthResponse.from_json(json)
      assert response.status == "healthy"
    end
  end

  describe "SupportedModel" do
    test "from_json/1 parses with string keys" do
      json = %{
        "model_id" => "llama-3-8b",
        "model_name" => "meta-llama/Meta-Llama-3-8B",
        "arch" => "llama"
      }

      model = SupportedModel.from_json(json)

      assert model.model_id == "llama-3-8b"
      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.arch == "llama"
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        model_id: "llama-3-8b",
        model_name: "meta-llama/Meta-Llama-3-8B",
        arch: "llama"
      }

      model = SupportedModel.from_json(json)

      assert model.model_id == "llama-3-8b"
      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.arch == "llama"
    end

    test "from_json/1 handles plain string (legacy format)" do
      model = SupportedModel.from_json("meta-llama/Meta-Llama-3-8B")

      assert model.model_id == nil
      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.arch == nil
    end

    test "from_json/1 handles missing fields" do
      json = %{"model_name" => "llama"}
      model = SupportedModel.from_json(json)

      assert model.model_id == nil
      assert model.model_name == "llama"
      assert model.arch == nil
    end
  end

  describe "GetServerCapabilitiesResponse" do
    test "from_json/1 parses with string keys" do
      json = %{
        "supported_models" => [
          %{
            "model_id" => "llama-3-8b",
            "model_name" => "meta-llama/Meta-Llama-3-8B",
            "arch" => "llama"
          },
          %{
            "model_id" => "qwen-2-7b",
            "model_name" => "Qwen/Qwen2-7B",
            "arch" => "qwen2"
          }
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      assert %SupportedModel{} = hd(response.supported_models)
      assert hd(response.supported_models).model_id == "llama-3-8b"
    end

    test "from_json/1 parses with atom keys" do
      json = %{
        supported_models: [
          %{model_id: "llama-3-8b", model_name: "llama", arch: "llama"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 1
    end

    test "from_json/1 handles legacy string format" do
      json = %{
        "supported_models" => ["llama", "qwen"]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      assert hd(response.supported_models).model_name == "llama"
    end

    test "from_json/1 handles mixed format" do
      json = %{
        "supported_models" => [
          %{"model_id" => "llama-3-8b", "model_name" => "llama"},
          "qwen"
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      assert hd(response.supported_models).model_id == "llama-3-8b"
      assert List.last(response.supported_models).model_name == "qwen"
    end

    test "from_json/1 defaults to empty list" do
      response = GetServerCapabilitiesResponse.from_json(%{})
      assert response.supported_models == []
    end

    test "from_json/1 filters nil values" do
      json = %{
        "supported_models" => [
          %{"model_name" => "llama"},
          nil,
          %{"model_name" => "qwen"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)
      assert length(response.supported_models) == 2
    end

    test "model_names/1 extracts model names" do
      response = %GetServerCapabilitiesResponse{
        supported_models: [
          %SupportedModel{model_name: "llama"},
          %SupportedModel{model_name: "qwen"},
          %SupportedModel{model_name: nil}
        ]
      }

      names = GetServerCapabilitiesResponse.model_names(response)
      assert names == ["llama", "qwen", nil]
    end
  end
end
