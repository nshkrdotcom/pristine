defmodule Pristine.OpenAPI.SecurityTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Security

  @reference_files [
    Path.expand("../../fixtures/openapi/security/get-self.yaml", __DIR__),
    Path.expand("../../fixtures/openapi/security/introspect-token.yaml", __DIR__)
  ]

  test "extracts security schemes and effective operation security for explicit fallback use" do
    metadata = Security.read(@reference_files)

    assert metadata.security == [%{"bearerAuth" => []}]
    assert metadata.security_schemes["bearerAuth"] == %{"scheme" => "bearer", "type" => "http"}
    assert metadata.security_schemes["basicAuth"] == %{"scheme" => "basic", "type" => "http"}

    assert metadata.operations[{:get, "/v1/users/me"}] == [%{"bearerAuth" => []}]
    assert metadata.operations[{:post, "/v1/oauth/introspect"}] == [%{"basicAuth" => []}]
  end
end
