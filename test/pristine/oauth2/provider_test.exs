defmodule Pristine.OAuth2.ProviderTest do
  use ExUnit.Case, async: true

  alias Pristine.Manifest
  alias Pristine.OAuth2.Provider

  test "uses x-pristine-flow to select a specific oauth2 flow from manifest security schemes" do
    {:ok, manifest} =
      Manifest.load(%{
        name: "demo",
        version: "0.1.0",
        base_url: "https://api.example.com",
        endpoints: [],
        types: %{},
        security_schemes: %{
          multiOauth: %{
            type: "oauth2",
            flows: %{
              authorizationCode: %{
                authorizationUrl: "/oauth/authorize",
                tokenUrl: "/oauth/token/code",
                scopes: %{"user.read" => "Read users"}
              },
              clientCredentials: %{
                tokenUrl: "/oauth/token/client",
                scopes: %{"admin.read" => "Read admin data"}
              }
            },
            "x-pristine-flow": "clientCredentials",
            "x-pristine-client-auth-method": "request_body",
            "x-pristine-token-method": "get"
          }
        }
      })

    assert {:ok, provider} = Provider.from_manifest(manifest, :multiOauth)
    assert provider.flow == :client_credentials
    assert provider.authorize_url == nil
    assert provider.token_url == "/oauth/token/client"
    assert provider.scopes == %{"admin.read" => "Read admin data"}
    assert provider.client_auth_method == :request_body
    assert provider.token_method == :get
  end

  test "falls back to a deterministic preferred oauth2 flow when no explicit flow is given" do
    {:ok, manifest} =
      Manifest.load(%{
        name: "demo",
        version: "0.1.0",
        base_url: "https://api.example.com",
        endpoints: [],
        types: %{},
        security_schemes: %{
          multiOauth: %{
            type: "oauth2",
            flows: %{
              clientCredentials: %{
                tokenUrl: "/oauth/token/client"
              },
              authorizationCode: %{
                authorizationUrl: "/oauth/authorize",
                tokenUrl: "/oauth/token/code"
              }
            }
          }
        }
      })

    assert {:ok, provider} = Provider.from_manifest(manifest, "multiOauth")
    assert provider.flow == :authorization_code
    assert provider.authorize_url == "/oauth/authorize"
    assert provider.token_url == "/oauth/token/code"
  end
end
