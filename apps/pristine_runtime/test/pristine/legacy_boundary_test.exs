defmodule Pristine.LegacyBoundaryTest do
  use ExUnit.Case, async: true

  @sdk_source_glob Path.expand("../../lib/pristine/sdk/**/*.ex", __DIR__)
  @openapi_source_glob Path.expand("../../lib/pristine/openapi/**/*.ex", __DIR__)
  @pristine_path Path.expand("../../lib/pristine.ex", __DIR__)
  @oauth_saved_token_path Path.expand("../../lib/pristine/oauth2/saved_token.ex", __DIR__)

  test "rebuilt SDK surface exists while the removed OpenAPI runtime stays absent" do
    sdk_sources = Path.wildcard(@sdk_source_glob)

    assert sdk_sources != []
    assert Path.wildcard(@openapi_source_glob) == []

    assert Code.ensure_loaded?(Pristine.SDK.Context)
    assert Code.ensure_loaded?(Pristine.SDK.Error)
    assert Code.ensure_loaded?(Pristine.SDK.Response)
    assert Code.ensure_loaded?(Pristine.SDK.ProviderProfile)
    assert Code.ensure_loaded?(Pristine.SDK.OpenAPI.Client)
    assert function_exported?(Pristine.SDK.OpenAPI.Client, :partition, 2)
    assert function_exported?(Pristine.SDK.OpenAPI.Client, :items, 2)
    assert function_exported?(Pristine.SDK.OpenAPI.Client, :next_page_request, 2)

    refute Code.ensure_loaded?(Pristine.SDK.OpenAPI.Operation)
    refute Code.ensure_loaded?(Pristine.OpenAPI.Runtime)
  end

  test "runtime source keeps both the manual and request-spec execution boundaries" do
    pristine = File.read!(@pristine_path)
    saved_token = File.read!(@oauth_saved_token_path)

    assert pristine =~ "Pristine.Client"
    assert pristine =~ "Pristine.Operation"
    assert pristine =~ "Pristine.SDK.Context"
    assert pristine =~ "Pristine.SDK.OpenAPI.Client"
    assert pristine =~ "def execute("
    assert pristine =~ "def context("
    assert pristine =~ "def foundation_context("
    assert pristine =~ "def execute_request("
    assert pristine =~ "def stream("

    refute pristine =~ "Pristine.OpenAPI"

    assert saved_token =~ "Pristine.OAuth2"
    refute saved_token =~ "Pristine.SDK.OAuth2"
  end
end
