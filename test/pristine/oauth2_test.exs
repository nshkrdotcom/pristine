defmodule Pristine.OAuth2Test do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.OAuth2
  alias Pristine.OAuth2.PKCE

  setup :set_mox_from_context
  setup :verify_on_exit!

  defp provider(overrides \\ []) do
    struct(
      Pristine.OAuth2.Provider,
      Keyword.merge(
        [
          name: "notion",
          flow: :authorization_code,
          site: "https://api.notion.com",
          authorize_url: "/v1/oauth/authorize",
          token_url: "/v1/oauth/token",
          revocation_url: "/v1/oauth/revoke",
          introspection_url: "/v1/oauth/introspect",
          scopes: %{"workspace.read" => "Read workspace"},
          default_scopes: ["workspace.read"],
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

  test "builds authorization requests with generated state and PKCE data" do
    assert {:ok, request} =
             OAuth2.authorization_request(provider(),
               client_id: "client-id",
               redirect_uri: "https://example.com/callback",
               generate_state: true,
               pkce: true,
               params: [owner: "user"]
             )

    assert is_binary(request.url)
    assert request.url =~ "client_id=client-id"
    assert request.url =~ "redirect_uri=https%3A%2F%2Fexample.com%2Fcallback"
    assert request.url =~ "scope=workspace.read"
    assert request.url =~ "owner=user"
    assert request.url =~ "code_challenge="
    assert request.url =~ "code_challenge_method=S256"
    assert is_binary(request.state)
    assert is_binary(request.pkce_verifier)
    assert is_binary(request.pkce_challenge)
    assert request.pkce_method == :s256
  end

  test "shapes explicit authorize URLs without hidden generated state" do
    verifier = "verifier-123"
    challenge = PKCE.challenge(verifier, :plain)

    assert {:ok, url} =
             OAuth2.authorize_url(provider(),
               client_id: "client-id",
               redirect_uri: "https://example.com/callback",
               state: "state-123",
               pkce_verifier: verifier,
               pkce_method: :plain
             )

    assert url =~ "state=state-123"
    assert url =~ "code_challenge=#{challenge}"
    assert url =~ "code_challenge_method=PLAIN"
  end

  test "exchanges an authorization code through Pristine transport for JSON token endpoints" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert request.method == :post
      assert request.url == "https://api.notion.com/v1/oauth/token"

      assert request.headers["authorization"] ==
               "Basic " <> Base.encode64("client-id:client-secret")

      assert request.headers["content-type"] == "application/json"

      assert Jason.decode!(request.body) == %{
               "code" => "auth-code",
               "grant_type" => "authorization_code",
               "redirect_uri" => "https://example.com/callback"
             }

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body:
           ~s({"access_token":"secret_123","refresh_token":"refresh_123","expires_in":3600,"token_type":"bearer"})
       }}
    end)

    assert {:ok, %Pristine.OAuth2.Token{} = token} =
             OAuth2.exchange_code(provider(), "auth-code",
               client_id: "client-id",
               client_secret: "client-secret",
               redirect_uri: "https://example.com/callback",
               context: oauth_context()
             )

    assert token.access_token == "secret_123"
    assert token.refresh_token == "refresh_123"
    assert token.token_type == "Bearer"
    assert is_integer(token.expires_at)
  end

  test "refreshes tokens through Pristine transport with request-body client auth" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert request.headers["content-type"] == "application/x-www-form-urlencoded"
      refute Map.has_key?(request.headers, "authorization")

      assert URI.decode_query(request.body) == %{
               "client_id" => "client-id",
               "client_secret" => "client-secret",
               "grant_type" => "refresh_token",
               "refresh_token" => "refresh_123"
             }

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body:
           ~s({"access_token":"secret_456","refresh_token":"refresh_456","token_type":"bearer"})
       }}
    end)

    assert {:ok, %Pristine.OAuth2.Token{access_token: "secret_456"}} =
             OAuth2.refresh_token(
               provider(
                 client_auth_method: :request_body,
                 token_content_type: "application/x-www-form-urlencoded"
               ),
               "refresh_123",
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context()
             )
  end

  test "supports public client token exchange without a client secret" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      refute Map.has_key?(request.headers, "authorization")

      assert URI.decode_query(request.body) == %{
               "client_id" => "public-client",
               "code" => "auth-code",
               "grant_type" => "authorization_code"
             }

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body: ~s({"access_token":"secret_public","token_type":"bearer"})
       }}
    end)

    assert {:ok, %Pristine.OAuth2.Token{access_token: "secret_public"}} =
             OAuth2.exchange_code(
               provider(
                 client_auth_method: :none,
                 token_content_type: "application/x-www-form-urlencoded"
               ),
               "auth-code",
               client_id: "public-client",
               context: oauth_context()
             )
  end
end
