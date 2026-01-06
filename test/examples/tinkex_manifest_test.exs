defmodule Examples.TinkexManifestTest do
  @moduledoc """
  Tests for the Tinkex example manifest.

  Verifies that the manifest loads correctly and contains all expected
  endpoints, types, and configuration.
  """

  use ExUnit.Case, async: true

  alias Pristine.Manifest

  @manifest_path "examples/tinkex/manifest.json"

  describe "tinkex manifest loading" do
    test "loads successfully" do
      assert {:ok, manifest} = Manifest.load_file(@manifest_path)
      assert manifest.name == "Tinkex"
      assert manifest.version == "1.0.0"
    end

    test "has all required endpoints" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      endpoint_ids = Map.keys(manifest.endpoints)

      assert "list_models" in endpoint_ids
      assert "get_model" in endpoint_ids
      assert "create_sample" in endpoint_ids
      assert "create_sample_stream" in endpoint_ids
      assert "get_sample" in endpoint_ids
      assert "create_sample_async" in endpoint_ids
    end

    test "has all required types" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      type_ids = Map.keys(manifest.types)

      assert "Model" in type_ids
      assert "ModelList" in type_ids
      assert "ApiSampleRequest" in type_ids
      assert "SampleResult" in type_ids
      assert "ContentBlock" in type_ids
      assert "SampleStreamEvent" in type_ids
      assert "AsyncSampleResponse" in type_ids
    end
  end

  describe "endpoint configuration" do
    test "models resource endpoints have correct paths" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      list_models = Map.get(manifest.endpoints, "list_models")
      get_model = Map.get(manifest.endpoints, "get_model")

      assert list_models.path == "/models"
      assert list_models.method == "GET"
      assert list_models.resource == "models"

      assert get_model.path == "/models/{model_id}"
      assert get_model.method == "GET"
      assert get_model.resource == "models"
    end

    test "sampling resource endpoints have correct configuration" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      create_sample = Map.get(manifest.endpoints, "create_sample")
      stream_endpoint = Map.get(manifest.endpoints, "create_sample_stream")

      assert create_sample.path == "/samples"
      assert create_sample.method == "POST"
      assert create_sample.resource == "sampling"
      assert create_sample.idempotency == true

      assert stream_endpoint.path == "/samples"
      assert stream_endpoint.streaming == true
    end

    test "streaming endpoint has stream configuration" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      stream_endpoint = Map.get(manifest.endpoints, "create_sample_stream")

      assert stream_endpoint.streaming == true
    end

    test "async endpoint has correct response type" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      async_endpoint = Map.get(manifest.endpoints, "create_sample_async")

      assert async_endpoint.response == "AsyncSampleResponse"
    end
  end

  describe "type definitions" do
    test "Model type has required fields" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      model_type = Map.get(manifest.types, "Model")
      fields = model_type.fields

      assert Map.has_key?(fields, "id")
      assert Map.has_key?(fields, "name")
      assert Map.has_key?(fields, "context_length")

      assert fields["id"].required == true
      assert fields["name"].required == true
      assert fields["context_length"].required == true
    end

    test "ApiSampleRequest type has prompt and model fields" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      sample_type = Map.get(manifest.types, "ApiSampleRequest")
      fields = sample_type.fields

      assert Map.has_key?(fields, "model")
      assert Map.has_key?(fields, "prompt")
      assert Map.has_key?(fields, "max_tokens")
      assert Map.has_key?(fields, "temperature")

      assert fields["model"].required == true
      assert fields["prompt"].required == true
    end

    test "SampleResult type has content and stop_reason" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      result_type = Map.get(manifest.types, "SampleResult")
      fields = result_type.fields

      assert Map.has_key?(fields, "id")
      assert Map.has_key?(fields, "content")
      assert Map.has_key?(fields, "stop_reason")
      assert Map.has_key?(fields, "usage")

      assert fields["stop_reason"].choices == [
               "end_turn",
               "max_tokens",
               "stop_sequence",
               "tool_use"
             ]
    end

    test "SampleStreamEvent has event type choices" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      event_type = Map.get(manifest.types, "SampleStreamEvent")
      fields = event_type.fields

      assert Map.has_key?(fields, "type")
      assert "message_start" in fields["type"].choices
      assert "content_block_delta" in fields["type"].choices
      assert "message_stop" in fields["type"].choices
    end

    test "AsyncSampleResponse has status choices" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      async_type = Map.get(manifest.types, "AsyncSampleResponse")
      fields = async_type.fields

      assert Map.has_key?(fields, "id")
      assert Map.has_key?(fields, "status")
      assert Map.has_key?(fields, "poll_url")

      assert fields["status"].choices == ["pending", "processing", "completed", "failed"]
    end
  end

  describe "policy configuration" do
    test "has default retry policy" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      assert Map.has_key?(manifest.policies, "default")

      default_policy = manifest.policies["default"]
      assert default_policy["max_attempts"] == 3
      assert default_policy["backoff"] == "exponential"
    end
  end
end
