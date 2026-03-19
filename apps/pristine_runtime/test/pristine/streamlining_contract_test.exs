defmodule Pristine.StreamliningContractTest do
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)
  @getting_started_path Path.expand("../../guides/getting-started.md", __DIR__)
  @oauth_path Path.expand("../../guides/oauth-and-token-sources.md", __DIR__)
  @pristine_path Path.expand("../../lib/pristine.ex", __DIR__)
  @pipeline_path Path.expand("../../lib/pristine/core/pipeline.ex", __DIR__)
  @result_classifier_port_path Path.expand(
                                 "../../lib/pristine/ports/result_classifier.ex",
                                 __DIR__
                               )

  @user_facing_docs [
    @readme_path,
    @getting_started_path,
    @oauth_path
  ]

  @tinkex_paths [
    Path.expand("../../examples/tinkex", __DIR__),
    Path.expand("../examples/tinkex_generation_test.exs", __DIR__),
    Path.expand("../examples/tinkex_manifest_test.exs", __DIR__),
    Path.expand("../integration/tinkex_mock_test.exs", __DIR__),
    Path.expand("../integration/tinkex_live_test.exs", __DIR__)
  ]

  @manifest_surface_paths [
    Path.expand("../../lib/pristine/manifest.ex", __DIR__),
    Path.expand("../../lib/pristine/manifest", __DIR__),
    Path.expand("../../lib/pristine/runtime.ex", __DIR__),
    Path.expand("../../lib/pristine/codegen.ex", __DIR__),
    Path.expand("../../lib/pristine/codegen", __DIR__),
    Path.expand("../../lib/pristine/docs.ex", __DIR__),
    Path.expand("../../lib/pristine/openapi.ex", __DIR__),
    Path.expand("../../lib/mix/tasks/pristine.generate.ex", __DIR__),
    Path.expand("../../lib/mix/tasks/pristine.validate.ex", __DIR__),
    Path.expand("../../lib/mix/tasks/pristine.docs.ex", __DIR__),
    Path.expand("../../lib/mix/tasks/pristine.openapi.ex", __DIR__),
    Path.expand("../../lib/pristine/ports/future.ex", __DIR__),
    Path.expand("../../lib/pristine/adapters/future/polling.ex", __DIR__)
  ]

  test "docs pin the hardened runtime boundary" do
    readme = File.read!(@readme_path)
    getting_started = File.read!(@getting_started_path)
    oauth_guide = File.read!(@oauth_path)

    assert readme =~ "`Pristine.execute_request/3`"
    assert readme =~ "`Pristine.foundation_context/1`"
    assert readme =~ "`Pristine.SDK.*`"
    assert getting_started =~ "`Pristine.execute_request/3`"
    assert getting_started =~ "`Pristine.foundation_context/1`"
    assert oauth_guide =~ "Pristine.SDK.OAuth2.Provider.from_security_scheme!"
    assert oauth_guide =~ "x-pristine-token-content-type"
  end

  test "docs pin SDK oauth provider construction to security scheme metadata" do
    oauth_guide = File.read!(@oauth_path)

    assert oauth_guide =~ "Pristine.SDK.OAuth2.Provider.from_security_scheme!"
    refute oauth_guide =~ "Pristine.OAuth2.Provider.from_manifest!"
    assert oauth_guide =~ "x-pristine-flow"
    assert oauth_guide =~ "x-pristine-token-content-type"
  end

  test "request execution path stays manifest-free internally" do
    pristine = File.read!(@pristine_path)
    pipeline = File.read!(@pipeline_path)
    result_classifier_port = File.read!(@result_classifier_port_path)

    assert pristine =~ "Pipeline.execute_request(request_spec, context, opts)"
    refute pristine =~ "Runtime.execute_request(request_spec, context, opts)"
    refute pristine =~ "load_manifest"
    refute pristine =~ "execute_endpoint"

    assert pipeline =~ "EndpointMetadata.from_request_spec("
    refute pipeline =~ "%Pristine.Manifest.Endpoint"
    refute pipeline =~ "execute_stream("
    refute pipeline =~ "execute_future("
    refute pipeline =~ "future_opts"

    assert result_classifier_port =~
             "Pristine.Core.{Context, EndpointMetadata, ResultClassification}"

    refute result_classifier_port =~ "Pristine.Manifest.Endpoint"
  end

  test "repo no longer carries the in-tree tinkex example surface" do
    lingering_paths = Enum.filter(@tinkex_paths, &File.exists?/1)
    assert lingering_paths == []
  end

  test "repo no longer carries the manifest-first runtime and task surface" do
    lingering_paths = Enum.filter(@manifest_surface_paths, &File.exists?/1)
    assert lingering_paths == []
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
end
