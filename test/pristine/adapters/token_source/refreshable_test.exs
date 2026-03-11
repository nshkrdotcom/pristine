defmodule Pristine.Adapters.TokenSource.RefreshableTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.TokenSource.Refreshable
  alias Pristine.OAuth2.Provider
  alias Pristine.OAuth2.Token

  defmodule RecordingTokenSource do
    @behaviour Pristine.Ports.TokenSource

    @impl true
    def fetch(opts) do
      send(self(), {:inner_fetch, opts})
      Process.get(:inner_fetch_result, :error)
    end

    @impl true
    def put(token, opts) do
      send(self(), {:inner_put, token, opts})
      Process.get(:inner_put_result, :ok)
    end
  end

  defmodule FakeOAuth2 do
    def refresh_token(provider, refresh_token, opts) do
      send(self(), {:oauth_refresh, provider, refresh_token, opts})

      Process.get(
        :oauth_refresh_result,
        {:ok, %Token{access_token: "refreshed-access", refresh_token: nil}}
      )
    end
  end

  setup do
    Process.delete(:inner_fetch_result)
    Process.delete(:inner_put_result)
    Process.delete(:oauth_refresh_result)
    :ok
  end

  test "refreshes expired tokens and persists the merged token" do
    Process.put(
      :inner_fetch_result,
      {:ok,
       %Token{
         access_token: "stale-access",
         refresh_token: "refresh-123",
         expires_at: System.system_time(:second) - 30,
         token_type: "Bearer",
         other_params: %{"workspace_name" => "Example Workspace"}
       }}
    )

    Process.put(
      :oauth_refresh_result,
      {:ok,
       %Token{
         access_token: "fresh-access",
         expires_at: System.system_time(:second) + 3600,
         other_params: %{"bot_id" => "bot-123"}
       }}
    )

    assert {:ok, %Token{} = token} =
             Refreshable.fetch(
               inner_source: {RecordingTokenSource, path: "/tmp/token.json"},
               provider: provider(),
               context: %Pristine.Core.Context{},
               client_id: "client-id",
               client_secret: "client-secret",
               oauth2_module: FakeOAuth2
             )

    assert token.access_token == "fresh-access"
    assert token.refresh_token == "refresh-123"

    assert token.other_params == %{
             "bot_id" => "bot-123",
             "workspace_name" => "Example Workspace"
           }

    assert_receive {:inner_fetch, [path: "/tmp/token.json"]}

    assert_receive {:oauth_refresh, %Provider{name: "example"}, "refresh-123", oauth_opts}
    assert oauth_opts[:client_id] == "client-id"
    assert oauth_opts[:client_secret] == "client-secret"
    assert match?(%Pristine.Core.Context{}, oauth_opts[:context])

    assert_receive {:inner_put, persisted_token, [path: "/tmp/token.json"]}
    assert persisted_token == token
  end

  test "returns a fresh token without refreshing" do
    fresh_token = %Token{
      access_token: "fresh-access",
      refresh_token: "refresh-123",
      expires_at: System.system_time(:second) + 3600
    }

    Process.put(:inner_fetch_result, {:ok, fresh_token})

    assert {:ok, ^fresh_token} =
             Refreshable.fetch(
               inner_source: {RecordingTokenSource, source: :memory},
               provider: provider(),
               oauth2_module: FakeOAuth2
             )

    assert_receive {:inner_fetch, [source: :memory]}
    refute_receive {:oauth_refresh, _, _, _}
    refute_receive {:inner_put, _, _}
  end

  test "persists rotated refresh tokens when the provider returns one" do
    Process.put(
      :inner_fetch_result,
      {:ok,
       %Token{
         access_token: "stale-access",
         refresh_token: "refresh-old",
         expires_at: System.system_time(:second) - 30
       }}
    )

    Process.put(
      :oauth_refresh_result,
      {:ok,
       %Token{
         access_token: "fresh-access",
         refresh_token: "refresh-rotated",
         expires_at: System.system_time(:second) + 3600
       }}
    )

    assert {:ok, %Token{refresh_token: "refresh-rotated"}} =
             Refreshable.fetch(
               inner_source: {RecordingTokenSource, id: "rotating"},
               provider: provider(),
               oauth2_module: FakeOAuth2
             )

    assert_receive {:inner_put, %Token{refresh_token: "refresh-rotated"}, [id: "rotating"]}
  end

  test "returns refresh failures from the oauth module" do
    Process.put(
      :inner_fetch_result,
      {:ok,
       %Token{
         access_token: "stale-access",
         refresh_token: "refresh-123",
         expires_at: System.system_time(:second) - 30
       }}
    )

    Process.put(:oauth_refresh_result, {:error, :refresh_failed})

    assert {:error, :refresh_failed} =
             Refreshable.fetch(
               inner_source: {RecordingTokenSource, source: :memory},
               provider: provider(),
               oauth2_module: FakeOAuth2
             )

    assert_receive {:oauth_refresh, %Provider{name: "example"}, "refresh-123", _opts}
    refute_receive {:inner_put, _, _}
  end

  test "does not invent expiry logic when expires_at is nil" do
    token = %Token{
      access_token: "opaque-access",
      refresh_token: "refresh-123",
      expires_at: nil
    }

    Process.put(:inner_fetch_result, {:ok, token})

    assert {:ok, ^token} =
             Refreshable.fetch(
               inner_source: {RecordingTokenSource, source: :memory},
               provider: provider(),
               oauth2_module: FakeOAuth2
             )

    assert_receive {:inner_fetch, [source: :memory]}
    refute_receive {:oauth_refresh, _, _, _}
    refute_receive {:inner_put, _, _}
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
