defmodule Pristine.LegacyBoundaryTest do
  use ExUnit.Case, async: true

  @sdk_source_glob Path.expand("../../lib/pristine/sdk/**/*.ex", __DIR__)
  @openapi_source_glob Path.expand("../../lib/pristine/openapi/**/*.ex", __DIR__)
  @pristine_path Path.expand("../../lib/pristine.ex", __DIR__)
  @oauth_saved_token_path Path.expand("../../lib/pristine/oauth2/saved_token.ex", __DIR__)

  test "legacy SDK and OpenAPI runtime surfaces are deleted" do
    assert Path.wildcard(@sdk_source_glob) == []
    assert Path.wildcard(@openapi_source_glob) == []

    refute Code.ensure_loaded?(Pristine.SDK.Context)
    refute Code.ensure_loaded?(Pristine.SDK.OpenAPI.Client)
    refute Code.ensure_loaded?(Pristine.SDK.OpenAPI.Operation)
    refute Code.ensure_loaded?(Pristine.OpenAPI.Runtime)
  end

  test "runtime source routes through client and operation instead of request-spec helpers" do
    pristine = File.read!(@pristine_path)
    saved_token = File.read!(@oauth_saved_token_path)

    assert pristine =~ "Pristine.Client"
    assert pristine =~ "Pristine.Operation"
    assert pristine =~ "def execute("
    assert pristine =~ "def stream("

    refute pristine =~ "def context("
    refute pristine =~ "def foundation_context("
    refute pristine =~ "def execute_request("
    refute pristine =~ "Pristine.SDK"
    refute pristine =~ "Pristine.OpenAPI"

    assert saved_token =~ "Pristine.OAuth2"
    refute saved_token =~ "Pristine.SDK.OAuth2"
  end
end
