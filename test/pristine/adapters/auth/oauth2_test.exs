defmodule Pristine.Adapters.Auth.OAuth2Test do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Auth.OAuth2
  alias Pristine.Adapters.TokenSource.Static
  alias Pristine.OAuth2.Token

  test "emits bearer headers from a token source" do
    token = %Token{access_token: "secret_123", token_type: "Bearer"}

    assert {:ok, headers} = OAuth2.headers(token_source: {Static, token: token})
    assert headers["Authorization"] == "Bearer secret_123"
  end

  test "fails clearly when the token source has no token" do
    assert {:error, :missing_oauth2_token} = OAuth2.headers(token_source: {Static, []})
  end
end
