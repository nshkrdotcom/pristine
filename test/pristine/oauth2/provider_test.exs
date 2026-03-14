defmodule Pristine.OAuth2.ProviderTest do
  use ExUnit.Case, async: true

  alias Pristine.OAuth2.Provider

  test "builds a provider directly from oauth2 security scheme metadata" do
    scheme = %{
      "type" => "oauth2",
      "flows" => %{
        "authorizationCode" => %{
          "authorizationUrl" => "/oauth/authorize",
          "tokenUrl" => "/oauth/token/code",
          "scopes" => %{"user.read" => "Read users"}
        },
        "clientCredentials" => %{
          "tokenUrl" => "/oauth/token/client",
          "scopes" => %{"admin.read" => "Read admin data"}
        }
      },
      "x-pristine-flow" => "clientCredentials",
      "x-pristine-default-scopes" => ["admin.read"],
      "x-pristine-client-auth-method" => "request_body",
      "x-pristine-token-method" => "get",
      "x-pristine-token-content-type" => "application/json",
      "x-pristine-revocation-url" => "/oauth/revoke",
      "x-pristine-introspection-url" => "/oauth/introspect",
      "x-extra" => "kept"
    }

    assert {:ok, provider} =
             Provider.from_security_scheme(:multiOauth, scheme, site: "https://api.example.com")

    assert provider.flow == :client_credentials
    assert provider.site == "https://api.example.com"
    assert provider.authorize_url == nil
    assert provider.token_url == "/oauth/token/client"
    assert provider.scopes == %{"admin.read" => "Read admin data"}
    assert provider.default_scopes == ["admin.read"]
    assert provider.client_auth_method == :request_body
    assert provider.token_method == :get
    assert provider.token_content_type == "application/json"
    assert provider.revocation_url == "/oauth/revoke"
    assert provider.introspection_url == "/oauth/introspect"

    assert provider.metadata == %{
             "x-pristine-flow" => "clientCredentials",
             "x-pristine-default-scopes" => ["admin.read"],
             "x-pristine-client-auth-method" => "request_body",
             "x-pristine-token-method" => "get",
             "x-pristine-token-content-type" => "application/json",
             "x-pristine-revocation-url" => "/oauth/revoke",
             "x-pristine-introspection-url" => "/oauth/introspect",
             "x-extra" => "kept"
           }
  end

  test "falls back to a deterministic preferred oauth2 flow when no explicit flow is given" do
    scheme = %{
      "type" => "oauth2",
      "flows" => %{
        "clientCredentials" => %{
          "tokenUrl" => "/oauth/token/client"
        },
        "authorizationCode" => %{
          "authorizationUrl" => "/oauth/authorize",
          "tokenUrl" => "/oauth/token/code"
        }
      }
    }

    assert {:ok, provider} = Provider.from_security_scheme("multiOauth", scheme)
    assert provider.flow == :authorization_code
    assert provider.authorize_url == "/oauth/authorize"
    assert provider.token_url == "/oauth/token/code"
  end
end
