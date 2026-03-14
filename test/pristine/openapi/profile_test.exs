defmodule Pristine.OpenAPI.ProfileTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Profile

  test "build/1 keeps pristine defaults while exposing supplemental and override hooks" do
    config =
      Profile.build(
        base_module: Pristine.OpenAPI.ProfileTest.Generated,
        output_dir: "/tmp/pristine-openapi-profile",
        supplemental_files: ["/tmp/example-supplement.yaml"],
        source_contexts: %{{:get, "/widgets"} => %{title: "Widgets reference"}},
        profile_overrides: [
          naming: [rename: [{"OAuth", "OAuth"}]],
          output: [types: [specs: :spec_comprehensive]]
        ]
      )

    assert Keyword.get(config, :processor) == OpenAPI.Processor
    assert Keyword.get(config, :renderer) == Pristine.OpenAPI.Renderer

    assert config |> Keyword.get(:reader) |> Keyword.get(:additional_files) == [
             "/tmp/example-supplement.yaml"
           ]

    output = Keyword.get(config, :output)

    assert Keyword.get(output, :base_module) == Pristine.OpenAPI.ProfileTest.Generated
    assert Keyword.get(output, :default_client) == Pristine.OpenAPI.Client
    assert Keyword.get(output, :location) == "/tmp/pristine-openapi-profile"
    assert Keyword.get(output, :operation_use) == Pristine.OpenAPI.Operation

    assert Keyword.get(output, :source_contexts) == %{
             {:get, "/widgets"} => %{title: "Widgets reference"}
           }

    assert Keyword.get(output, :security_metadata) == nil
    assert output |> Keyword.get(:types) |> Keyword.get(:error) == Pristine.Error
    assert output |> Keyword.get(:types) |> Keyword.get(:specs) == :spec_comprehensive

    assert config |> Keyword.get(:naming) |> Keyword.get(:rename) == [{"OAuth", "OAuth"}]
  end

  test "build/1 ignores explicit security metadata fallback hooks" do
    fallback = %{operations: %{{:get, "/widgets"} => [%{"bearerAuth" => []}]}}

    output =
      Profile.build(
        base_module: Pristine.OpenAPI.ProfileTest.Generated,
        output_dir: "/tmp/pristine-openapi-profile",
        security_metadata: fallback
      )
      |> Keyword.get(:output)

    assert Keyword.get(output, :security_metadata) == nil
  end
end
