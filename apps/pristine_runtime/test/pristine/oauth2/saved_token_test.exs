defmodule Pristine.OAuth2.SavedTokenTest do
  use ExUnit.Case, async: true

  alias Pristine.OAuth2.Provider
  alias Pristine.OAuth2.SavedToken
  alias Pristine.OAuth2.Token

  defmodule RecordingTokenSource do
    @behaviour Pristine.Ports.TokenSource

    @impl true
    def fetch(opts) do
      send(self(), {:token_source_fetch, opts})
      Process.get(:saved_token_fetch_result, :error)
    end

    @impl true
    def put(token, opts) do
      send(self(), {:token_source_put, token, opts})
      Process.get(:saved_token_put_result, :ok)
    end
  end

  defmodule FakeOAuth2 do
    def refresh_token(provider, refresh_token, opts) do
      send(self(), {:oauth_refresh, provider, refresh_token, opts})

      Process.get(
        :saved_token_refresh_result,
        {:ok, Token.from_map(%{access_token: "refreshed-access"})}
      )
    end
  end

  setup do
    Process.delete(:saved_token_fetch_result)
    Process.delete(:saved_token_put_result)
    Process.delete(:saved_token_refresh_result)
    :ok
  end

  test "refreshes a persisted token, preserves rotated refresh tokens, and merges metadata" do
    Process.put(
      :saved_token_fetch_result,
      {:ok,
       Token.from_map(%{
         access_token: "saved-access",
         refresh_token: "refresh-old",
         other_params: %{"workspace_name" => "Example Workspace"}
       })}
    )

    Process.put(
      :saved_token_refresh_result,
      {:ok,
       Token.from_map(%{
         access_token: "refreshed-access",
         refresh_token: "refresh-rotated",
         other_params: %{"workspace_id" => "workspace-123"}
       })}
    )

    assert {:ok, token} =
             SavedToken.refresh(provider(),
               token_source: {RecordingTokenSource, path: "/tmp/notion.json"},
               client_id: "client-id",
               client_secret: "client-secret",
               context: %Pristine.Core.Context{},
               oauth2_module: FakeOAuth2
             )

    assert token.access_token == "refreshed-access"
    assert token.refresh_token == "refresh-rotated"

    assert token.other_params == %{
             "workspace_id" => "workspace-123",
             "workspace_name" => "Example Workspace"
           }

    assert_receive {:token_source_fetch, [path: "/tmp/notion.json"]}
    assert_receive {:oauth_refresh, %Provider{name: "example"}, "refresh-old", refresh_opts}
    assert refresh_opts[:client_id] == "client-id"
    assert refresh_opts[:client_secret] == "client-secret"
    assert match?(%Pristine.Core.Context{}, refresh_opts[:context])
    assert_receive {:token_source_put, ^token, [path: "/tmp/notion.json"]}
  end

  test "returns a structured error when the saved token does not contain a refresh token" do
    Process.put(
      :saved_token_fetch_result,
      {:ok, Token.from_map(%{access_token: "saved-access"})}
    )

    assert {:error, :missing_refresh_token} =
             SavedToken.refresh(provider(),
               token_source: {RecordingTokenSource, path: "/tmp/notion.json"},
               oauth2_module: FakeOAuth2
             )

    assert_receive {:token_source_fetch, [path: "/tmp/notion.json"]}
    refute_receive {:oauth_refresh, _, _, _}
    refute_receive {:token_source_put, _, _}
  end

  defp provider do
    Provider.new(
      name: "example",
      flow: :authorization_code,
      site: "https://api.example.com",
      token_url: "/oauth/token",
      client_auth_method: :basic
    )
  end
end
