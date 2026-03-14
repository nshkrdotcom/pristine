defmodule Pristine.OAuth2.BackendPortTest do
  use ExUnit.Case, async: false
  import Mox

  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.OAuth2
  alias Pristine.OAuth2.Provider
  alias Pristine.Ports.OAuthBackend.Request, as: BackendRequest

  setup :set_mox_from_context
  setup :verify_on_exit!

  defmodule FakeBackend do
    @behaviour Pristine.Ports.OAuthBackend

    alias Pristine.OAuth2.Token
    alias Pristine.Ports.OAuthBackend.Request, as: BackendRequest

    @impl true
    def available?, do: true

    @impl true
    def authorization_url(provider, opts) do
      send(self(), {:backend_authorization_url, provider, opts})
      {:ok, "https://auth.example.test/authorize?client_id=#{Keyword.fetch!(opts, :client_id)}"}
    end

    @impl true
    def build_request(provider, kind, params, opts) do
      send(self(), {:backend_build_request, provider, kind, params, opts})

      {:ok,
       %BackendRequest{
         method: :post,
         url: "https://auth.example.test/request",
         headers: %{"content-type" => "application/json"},
         body: Jason.encode!(%{"kind" => inspect(kind), "params" => Map.new(params)})
       }}
    end

    @impl true
    def normalize_token_response(provider, body) do
      send(self(), {:backend_token_response, provider, body})

      {:ok,
       Token.from_map(%{
         access_token: Map.fetch!(body, "access_token"),
         refresh_token: Map.get(body, "refresh_token"),
         other_params: Map.drop(body, ["access_token", "refresh_token"])
       })}
    end
  end

  setup do
    previous_backend = Application.get_env(:pristine, :oauth_backend)
    Application.put_env(:pristine, :oauth_backend, FakeBackend)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:pristine, :oauth_backend, previous_backend)
      else
        Application.delete_env(:pristine, :oauth_backend)
      end
    end)

    :ok
  end

  test "authorization requests are resolved through the backend port" do
    assert {:ok, request} =
             OAuth2.authorization_request(provider(),
               client_id: "client-id",
               redirect_uri: "https://example.com/callback",
               state: "state-123",
               params: [owner: "user"]
             )

    assert request.url == "https://auth.example.test/authorize?client_id=client-id"

    assert_receive {:backend_authorization_url, %Provider{name: "example"}, opts}
    assert opts[:client_id] == "client-id"
    assert opts[:redirect_uri] == "https://example.com/callback"
    assert opts[:params][:owner] == "user"
    assert opts[:params][:state] == "state-123"
  end

  test "token exchange and control requests are shaped through the backend port" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert request.method == :post
      assert request.url == "https://auth.example.test/request"
      assert request.headers["content-type"] == "application/json"

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body:
           Jason.encode!(%{
             "access_token" => "secret-access",
             "refresh_token" => "refresh-access",
             "workspace_name" => "Example Workspace"
           })
       }}
    end)

    assert {:ok, token} =
             OAuth2.exchange_code(provider(), "auth-code",
               client_id: "client-id",
               client_secret: "client-secret",
               redirect_uri: "https://example.com/callback",
               context: oauth_context()
             )

    assert token.access_token == "secret-access"
    assert token.refresh_token == "refresh-access"
    assert token.other_params["workspace_name"] == "Example Workspace"

    assert_receive {:backend_build_request, %Provider{name: "example"},
                    {:token, :authorization_code}, params, opts}

    assert params[:code] == "auth-code"
    assert params[:redirect_uri] == "https://example.com/callback"
    assert opts[:client_id] == "client-id"
    assert opts[:client_secret] == "client-secret"

    assert_receive {:backend_token_response, %Provider{name: "example"},
                    %{
                      "access_token" => "secret-access",
                      "refresh_token" => "refresh-access",
                      "workspace_name" => "Example Workspace"
                    }}
  end

  test "oauth control requests use the backend port without inheriting bearer auth behavior" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert request.url == "https://auth.example.test/request"

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body: Jason.encode!(%{"active" => true})
       }}
    end)

    assert {:ok, %{"active" => true}} =
             OAuth2.introspect_token(provider(), "secret-token",
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context()
             )

    assert_receive {:backend_build_request, %Provider{name: "example"}, :introspect, params,
                    _opts}

    assert params == %{token: "secret-token"}
  end

  defp provider(overrides \\ []) do
    struct(
      Provider,
      Keyword.merge(
        [
          name: "example",
          flow: :authorization_code,
          site: "https://api.example.com",
          authorize_url: "/oauth/authorize",
          token_url: "/oauth/token",
          revocation_url: "/oauth/revoke",
          introspection_url: "/oauth/introspect",
          client_auth_method: :basic,
          token_method: :post,
          token_content_type: "application/json"
        ],
        overrides
      )
    )
  end

  defp oauth_context do
    %Context{
      transport: Pristine.TransportMock,
      serializer: Pristine.Adapters.Serializer.JSON
    }
  end
end
