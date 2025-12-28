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
end
