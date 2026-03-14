defmodule Pristine.StreamliningContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @code_generation_path Path.expand("../../guides/code-generation.md", __DIR__)

  @user_facing_docs [
    @readme_path,
    @getting_started_path,
    @code_generation_path
  ]

  @tinkex_paths [
    Path.expand("../../examples/tinkex", __DIR__),
    Path.expand("../examples/tinkex_generation_test.exs", __DIR__),
    Path.expand("../examples/tinkex_manifest_test.exs", __DIR__),
    Path.expand("../integration/tinkex_mock_test.exs", __DIR__),
    Path.expand("../integration/tinkex_live_test.exs", __DIR__)
  ]

  test "docs pin the hardened runtime boundary and retained bridge seam" do
    readme = File.read!(@readme_path)
    getting_started = File.read!(@getting_started_path)
    code_generation = File.read!(@code_generation_path)

    assert readme =~ "`Pristine.execute_request/3`"
    assert readme =~ "`Pristine.foundation_context/1`"
    assert readme =~ "`Pristine.SDK.*`"
    assert getting_started =~ "`Pristine.execute_request/3`"
    assert getting_started =~ "`Pristine.foundation_context/1`"
    assert code_generation =~ "`Pristine.OpenAPI.Bridge.run/3` is the retained first-party"
    assert code_generation =~ "build-time seam for"
    assert code_generation =~ "It is not the normal consumer runtime entry"
  end

  test "docs pin SDK oauth provider construction to security scheme metadata" do
    readme = File.read!(@readme_path)
    code_generation = File.read!(@code_generation_path)

    assert readme =~ "Pristine.SDK.OAuth2.Provider.from_security_scheme!"
    refute readme =~ "Pristine.OAuth2.Provider.from_manifest!"

    assert code_generation =~ "Pristine.SDK.OAuth2.Provider.from_security_scheme!"
    assert code_generation =~ "x-pristine-flow"
    assert code_generation =~ "x-pristine-token-content-type"
  end

  test "user-facing docs do not advertise an in-tree tinkex example app" do
    mentions =
      Enum.flat_map(@user_facing_docs, fn path ->
        source = File.read!(path)

        if String.contains?(source, "examples/tinkex") or String.contains?(source, "Tinkex") do
          [path]
        else
          []
        end
      end)

    assert mentions == []
  end

  test "repo no longer carries the in-tree tinkex example surface" do
    lingering_paths = Enum.filter(@tinkex_paths, &File.exists?/1)
    assert lingering_paths == []
  end
end
