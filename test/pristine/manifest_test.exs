defmodule Pristine.ManifestTest do
  use ExUnit.Case, async: true

  alias Pristine.Manifest

  test "loads and normalizes a manifest" do
    input = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{
          id: :sample,
          method: :post,
          path: "/sampling",
          request: "SampleRequest",
          response: "SampleResponse",
          retry: "default"
        }
      ],
      types: %{
        "SampleRequest" => %{
          fields: %{
            prompt: %{type: "string", required: true},
            sampling_params: %{type: "string", required: true}
          }
        },
        "SampleResponse" => %{
          fields: %{
            text: %{type: "string", required: true}
          }
        }
      }
    }

    assert {:ok, %Manifest{} = manifest} = Manifest.load(input)
    assert manifest.name == "tinkex"
    assert manifest.version == "0.3.4"
    assert Map.has_key?(manifest.endpoints, "sample")
    assert manifest.endpoints["sample"].method == "POST"
    assert manifest.endpoints["sample"].path == "/sampling"
  end

  test "rejects missing required manifest fields" do
    input = %{name: "bad"}

    assert {:error, errors} = Manifest.load(input)
    assert Enum.any?(errors, &String.contains?(&1, "version"))
    assert Enum.any?(errors, &String.contains?(&1, "endpoints"))
    assert Enum.any?(errors, &String.contains?(&1, "types"))
  end

  test "rejects invalid endpoint definitions" do
    input = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{id: "sample", method: "POST", path: "sampling"}
      ],
      types: %{}
    }

    assert {:error, errors} = Manifest.load(input)
    assert Enum.any?(errors, &String.contains?(&1, "endpoint sample"))
  end

  test "loads tinkex manifest fixture with extended fields" do
    path = Path.expand("../fixtures/tinkex_manifest.json", __DIR__)

    assert {:ok, %Manifest{} = manifest} = Manifest.load_file(path)
    assert manifest.base_url == "https://api.tinker.ai/v1"
    assert manifest.auth["type"] == "api_key"
    assert manifest.defaults["timeout"] == 60_000
    assert manifest.error_types["400"]["name"] == "BadRequestError"
    assert manifest.retry_policies["default"]["max_attempts"] == 3
    assert manifest.rate_limits["standard"]["limit"] == 10

    create_model = manifest.endpoints["create_model"]
    assert create_model.async == true
    assert create_model.poll_endpoint == "retrieve_future"
    assert create_model.timeout == 300_000
    assert create_model.idempotency_header == "X-Idempotency-Key"
    assert create_model.deprecated == false
    assert create_model.tags == ["models", "training"]
    assert create_model.error_types == ["BadRequestError"]
    assert create_model.response_unwrap == "data.result"

    stream_ep = manifest.endpoints["sample_stream"]
    assert stream_ep.streaming == true
    assert stream_ep.stream_format == "sse"
    assert stream_ep.event_types == ["message_start", "message_stop"]

    union = manifest.types["ModelInputChunk"]
    assert union.kind == :union
    assert union.discriminator.field == "type"
    assert union.discriminator.mapping["text"] == "TextChunk"

    literal_field = manifest.types["CreateModelRequest"].fields["type"]
    assert literal_field[:type] == "literal"
    assert literal_field[:value] == "create_model"

    ref_field = manifest.types["SampleRequest"].fields["prompt"]
    assert ref_field[:type_ref] == "ModelInput"

    items = manifest.types["ModelInput"].fields["chunks"][:items]
    assert items[:type_ref] == "ModelInputChunk"
  end
end
