defmodule Pristine.CodegenTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen

  test "build_sources returns files for types and client" do
    manifest = %{
      name: "demo",
      version: "0.1.0",
      endpoints: [
        %{
          id: "sample",
          method: "POST",
          path: "/sampling",
          request: "SampleRequest",
          response: "SampleResponse"
        }
      ],
      types: %{
        "SampleRequest" => %{fields: %{prompt: %{type: "string", required: true}}}
      }
    }

    assert {:ok, sources} = Codegen.build_sources(manifest, output_dir: "lib/generated")
    assert Map.has_key?(sources, "lib/generated/types/sample_request.ex")
    assert Map.has_key?(sources, "lib/generated/client.ex")
  end
end
