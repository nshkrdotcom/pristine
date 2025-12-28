defmodule Integration.TinkexLiveTest do
  @moduledoc """
  Live API integration tests for Tinkex.

  These tests run against the actual Tinker API when TINKER_API_KEY
  environment variable is set. They are skipped by default.

  ## Running Live Tests

      TINKER_API_KEY=your-key mix test test/integration/tinkex_live_test.exs

  ## Notes

  - These tests make real API calls and may incur costs
  - Tests are designed to be idempotent and non-destructive
  - Rate limiting may affect test execution
  """

  use ExUnit.Case, async: false

  alias Pristine.Manifest
  alias Pristine.Core.Context
  alias Pristine.Core.Pipeline

  @moduletag :live_api
  @moduletag timeout: 60_000

  @manifest_path "examples/tinkex/manifest.json"

  setup do
    api_key = System.get_env("TINKER_API_KEY")

    if is_nil(api_key) do
      :skip
    else
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      context =
        Context.new(
          base_url: "https://api.tinker.ai/v1",
          transport: Pristine.Adapters.Transport.Finch,
          serializer: Pristine.Adapters.Serializer.JSON,
          auth: [Pristine.Adapters.Auth.Bearer.new(api_key)]
        )

      {:ok, manifest: manifest, context: context}
    end
  end

  describe "live API - models" do
    @tag :live_api
    test "list_models returns real models", %{manifest: manifest, context: context} do
      {:ok, result} = Pipeline.execute(manifest, "list_models", %{}, context)

      assert is_map(result)
      assert is_list(result["data"])
      assert length(result["data"]) > 0

      model = Enum.at(result["data"], 0)
      assert is_binary(model["id"])
      assert is_integer(model["context_length"])
    end

    @tag :live_api
    test "get_model returns model details", %{manifest: manifest, context: context} do
      # First, list models to get a valid model ID
      {:ok, list_result} = Pipeline.execute(manifest, "list_models", %{}, context)
      model_id = Enum.at(list_result["data"], 0)["id"]

      {:ok, model} =
        Pipeline.execute(manifest, "get_model", %{}, context,
          path_params: %{"model_id" => model_id}
        )

      assert model["id"] == model_id
      assert is_binary(model["name"])
    end
  end

  describe "live API - sampling" do
    @tag :live_api
    test "create_sample generates text", %{manifest: manifest, context: context} do
      # First, get a model ID
      {:ok, list_result} = Pipeline.execute(manifest, "list_models", %{}, context)
      model_id = Enum.at(list_result["data"], 0)["id"]

      request = %{
        "model" => model_id,
        "prompt" => "Say hello in exactly 3 words.",
        "max_tokens" => 20
      }

      {:ok, result} = Pipeline.execute(manifest, "create_sample", request, context)

      assert is_binary(result["id"])
      assert length(result["content"]) > 0

      text_block = Enum.find(result["content"], &(&1["type"] == "text"))
      assert is_binary(text_block["text"])
      assert String.length(text_block["text"]) > 0
    end

    @tag :live_api
    test "create_sample respects max_tokens", %{manifest: manifest, context: context} do
      {:ok, list_result} = Pipeline.execute(manifest, "list_models", %{}, context)
      model_id = Enum.at(list_result["data"], 0)["id"]

      request = %{
        "model" => model_id,
        "prompt" => "Count from 1 to 1000.",
        "max_tokens" => 5
      }

      {:ok, result} = Pipeline.execute(manifest, "create_sample", request, context)

      # With max_tokens: 5, should stop early
      assert result["stop_reason"] == "max_tokens" or
               String.length(hd(result["content"])["text"]) < 50
    end
  end

  describe "live API - error handling" do
    @tag :live_api
    test "returns error for invalid model", %{manifest: manifest, context: context} do
      request = %{
        "model" => "definitely-not-a-real-model-id",
        "prompt" => "Hello",
        "max_tokens" => 10
      }

      {:error, _error} = Pipeline.execute(manifest, "create_sample", request, context)
    end

    @tag :live_api
    test "returns error for missing required field", %{manifest: manifest, context: context} do
      request = %{
        # Missing model and prompt
        "max_tokens" => 10
      }

      {:error, _error} = Pipeline.execute(manifest, "create_sample", request, context)
    end
  end
end
