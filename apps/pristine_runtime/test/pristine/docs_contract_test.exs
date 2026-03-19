defmodule Pristine.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @oauth_path Path.expand("../../guides/oauth-and-token-sources.md", __DIR__)

  @public_docs [
    @readme_path,
    @getting_started_path,
    @oauth_path
  ]

  @removed_contract_markers [
    "mix pristine.generate",
    "mix pristine.validate",
    "mix pristine.docs",
    "mix pristine.openapi",
    "Pristine.load_manifest",
    "Pristine.load_manifest_file",
    "Pristine.execute(",
    "Pristine.execute_endpoint(",
    "Pristine.Runtime",
    "Pristine.Manifest",
    "Pristine.Codegen",
    "Pristine.Docs",
    "future polling",
    "Pristine.Ports.Future",
    "Pristine.Adapters.Future.Polling"
  ]

  test "runtime docs advertise the retained runtime boundary" do
    readme = File.read!(@readme_path)
    getting_started = File.read!(@getting_started_path)
    oauth_guide = File.read!(@oauth_path)

    assert readme =~ "`Pristine.execute_request/3`"
    assert readme =~ "`Pristine.foundation_context/1`"
    assert readme =~ "`Pristine.SDK.*`"
    assert getting_started =~ "`Pristine.execute_request/3`"
    assert getting_started =~ "`Pristine.foundation_context/1`"
    assert oauth_guide =~ "Pristine.SDK.OAuth2.Provider.from_security_scheme!"
    assert oauth_guide =~ "x-pristine-flow"
  end

  test "runtime docs do not advertise the removed manifest-first surface" do
    violations =
      Enum.flat_map(@public_docs, fn path ->
        source = File.read!(path)

        Enum.flat_map(@removed_contract_markers, fn marker ->
          if String.contains?(source, marker) do
            ["#{path}: #{marker}"]
          else
            []
          end
        end)
      end)

    assert violations == []
  end
end
