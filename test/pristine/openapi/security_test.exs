defmodule Pristine.OpenAPI.SecurityTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Security

  @reference_dir "/home/home/p/g/n/jido_brainstorm/nshkrdotcom/notion_sdk/priv/upstream/reference"

  test "extracts security schemes and effective operation security for explicit fallback use" do
    metadata =
      Security.read([
        Path.join(@reference_dir, "get-self.yaml"),
        Path.join(@reference_dir, "introspect-token.yaml")
      ])

    assert metadata.security == [%{"bearerAuth" => []}]
    assert metadata.security_schemes["bearerAuth"] == %{"scheme" => "bearer", "type" => "http"}
    assert metadata.security_schemes["basicAuth"] == %{"scheme" => "basic", "type" => "http"}

    assert metadata.operations[{:get, "/v1/users/me"}] == [%{"bearerAuth" => []}]
    assert metadata.operations[{:post, "/v1/oauth/introspect"}] == [%{"basicAuth" => []}]
  end
end
