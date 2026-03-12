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
  end

  test "rejects invalid top-level manifest types" do
    input = %{
      name: "demo",
      version: "0.1.0",
      endpoints: %{},
      types: []
    }

    assert {:error, errors} = Manifest.load(input)
    assert Enum.any?(errors, &String.contains?(&1, "endpoints"))
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

  test "rejects deprecated policies key" do
    input = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{id: "sample", method: "POST", path: "/sampling"}
      ],
      types: %{},
      policies: %{
        default: %{max_attempts: 3}
      }
    }

    assert {:error, errors} = Manifest.load(input)
    assert "policies has been removed; use retry_policies" in errors
  end

  test "rejects colon-style path params" do
    input = %{
      name: "tinkex",
      version: "0.3.4",
      endpoints: [
        %{id: "sample", method: "POST", path: "/sampling/:id"}
      ],
      types: %{}
    }

    assert {:error, errors} = Manifest.load(input)
    assert "endpoint sample path params must use {param} syntax" in errors
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
    refute Map.has_key?(Map.from_struct(manifest), :policies)
  end

  test "applies manifest endpoint defaults during normalization" do
    input = %{
      name: "demo",
      version: "0.1.0",
      defaults: %{
        timeout: 30_000,
        retry: "default",
        headers: %{"X-App" => "pristine", "X-Shared" => "default"}
      },
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sample",
          headers: %{"X-Shared" => "endpoint", "X-Endpoint" => "1"}
        }
      ],
      types: %{}
    }

    assert {:ok, manifest} = Manifest.load(input)

    endpoint = manifest.endpoints["sample"]

    assert endpoint.timeout == 30_000
    assert endpoint.retry == "default"
    assert endpoint.headers["X-App"] == "pristine"
    assert endpoint.headers["X-Shared"] == "endpoint"
    assert endpoint.headers["X-Endpoint"] == "1"
  end

  test "loads top-level and endpoint security metadata while preserving auth fields" do
    input = %{
      name: "demo",
      version: "0.1.0",
      auth: %{type: "bearer"},
      security_schemes: %{
        bearerAuth: %{
          type: "http",
          scheme: "bearer"
        },
        notionOauth: %{
          type: "oauth2",
          flows: %{
            authorizationCode: %{
              authorizationUrl: "https://api.notion.com/v1/oauth/authorize",
              tokenUrl: "https://api.notion.com/v1/oauth/token",
              scopes: %{"workspace.read" => "Read workspace"}
            }
          }
        }
      },
      security: [
        %{bearerAuth: []}
      ],
      endpoints: [
        %{
          id: "list_users",
          method: "GET",
          path: "/v1/users",
          security: [%{bearerAuth: []}]
        },
        %{
          id: "oauth_token",
          method: "POST",
          path: "/v1/oauth/token",
          auth: "basicAuth",
          security: [%{notionOauth: ["workspace.read"]}]
        }
      ],
      types: %{}
    }

    assert {:ok, manifest} = Manifest.load(input)

    assert manifest.auth == %{"type" => "bearer"}
    assert manifest.security == [%{"bearerAuth" => []}]
    assert manifest.security_schemes["bearerAuth"]["scheme"] == "bearer"

    assert manifest.security_schemes["notionOauth"]["flows"]["authorizationCode"]["tokenUrl"] ==
             "https://api.notion.com/v1/oauth/token"

    assert manifest.endpoints["list_users"].security == [%{"bearerAuth" => []}]
    assert manifest.endpoints["oauth_token"].auth == "basicAuth"
    assert manifest.endpoints["oauth_token"].security == [%{"notionOauth" => ["workspace.read"]}]
  end

  test "preserves alias array item definitions" do
    input = %{
      name: "demo",
      version: "0.1.0",
      endpoints: [%{id: "list", method: "GET", path: "/list"}],
      types: %{
        "TagList" => %{
          type: "array",
          items: "string"
        }
      }
    }

    assert {:ok, manifest} = Manifest.load(input)
    assert manifest.types["TagList"].kind == :alias
    assert manifest.types["TagList"].items == %{type: "string"}
  end
end
