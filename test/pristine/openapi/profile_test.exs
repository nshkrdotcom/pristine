defmodule Pristine.OpenAPI.ProfileTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Profile

  test "build/1 keeps defaults while exposing supplemental and override hooks" do
    config =
      Profile.build(
        base_module: Pristine.OpenAPI.ProfileTest.Generated,
        output_dir: "/tmp/pristine-openapi-profile",
        supplemental_files: ["/tmp/notion-supplement.yaml"],
        profile_overrides: [
          naming: [rename: [{"OAuth", "OAuth"}]],
          output: [types: [error: Pristine.Error]]
        ]
      )

    assert Keyword.get(config, :processor) == OpenAPI.Processor
    assert Keyword.get(config, :renderer) == OpenAPI.Renderer

    assert config |> Keyword.get(:reader) |> Keyword.get(:additional_files) == [
             "/tmp/notion-supplement.yaml"
           ]

    output = Keyword.get(config, :output)

    assert Keyword.get(output, :base_module) == Pristine.OpenAPI.ProfileTest.Generated
    assert Keyword.get(output, :default_client) == Pristine.OpenAPI.Client
    assert Keyword.get(output, :location) == "/tmp/pristine-openapi-profile"
    assert output |> Keyword.get(:types) |> Keyword.get(:error) == Pristine.Error

    assert config |> Keyword.get(:naming) |> Keyword.get(:rename) == [{"OAuth", "OAuth"}]
  end
end
