defmodule Pristine.DocsContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @foundation_path Path.expand("../../guides/foundation-runtime.md", __DIR__)
  @manual_path Path.expand("../../guides/manual-contexts-and-adapters.md", __DIR__)
  @oauth_path Path.expand("../../guides/oauth-and-token-sources.md", __DIR__)
  @streaming_path Path.expand("../../guides/streaming-and-sse.md", __DIR__)

  @public_docs [
    @readme_path,
    @getting_started_path,
    @foundation_path,
    @manual_path,
    @oauth_path,
    @streaming_path
  ]

  @removed_contract_markers [
    "Pristine.context(",
    "Pristine.foundation_context(",
    "Pristine.execute_request(",
    "Pristine.SDK",
    "Pristine.SDK.OpenAPI",
    "Pristine.OpenAPI",
    "Pristine.OpenAPI.Runtime",
    "GeneratedSupport"
  ]

  test "runtime docs advertise the rebuilt runtime boundary" do
    readme = File.read!(@readme_path)
    getting_started = File.read!(@getting_started_path)
    foundation = File.read!(@foundation_path)
    manual = File.read!(@manual_path)
    streaming = File.read!(@streaming_path)
    oauth_guide = File.read!(@oauth_path)

    assert readme =~ "`Pristine.Client`"
    assert readme =~ "`Pristine.Operation`"
    assert readme =~ "`Pristine.execute/3`"
    assert readme =~ "`Pristine.stream/3`"

    assert getting_started =~ "`Pristine.Client`"
    assert getting_started =~ "`Pristine.Operation`"
    assert getting_started =~ "`Pristine.execute/3`"

    assert foundation =~ "Pristine.Client.foundation/1"
    assert manual =~ "Pristine.Client.new/1"
    assert streaming =~ "Pristine.stream/3"
    assert oauth_guide =~ "Pristine.OAuth2.Provider.from_security_scheme!"
    assert oauth_guide =~ "`Pristine.OAuth2`"
  end

  test "runtime docs do not advertise the removed SDK and request-spec surface" do
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
