defmodule Pristine.OAuth2.InteractiveTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.OAuth2
  alias Pristine.OAuth2.Error
  alias Pristine.OAuth2.Interactive

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Process.put(:interactive_test_pid, self())
    on_exit(fn -> Process.delete(:interactive_test_pid) end)
    :ok
  end

  defmodule FakeBrowser do
    def open(url, _opts) do
      send(Process.get(:interactive_test_pid), {:browser_open, url})
      Process.get(:browser_result, :ok)
    end
  end

  defmodule FakeCallbackServer do
    def start(redirect_uri, opts) do
      send(Process.get(:interactive_test_pid), {:callback_server_start, redirect_uri, opts})
      {:ok, %{redirect_uri: redirect_uri}}
    end

    def await(server, timeout_ms) do
      send(Process.get(:interactive_test_pid), {:callback_server_await, server, timeout_ms})
      Process.get(:callback_server_result)
    end

    def stop(server) do
      send(Process.get(:interactive_test_pid), {:callback_server_stop, server})
      :ok
    end
  end

  defp provider(overrides \\ []) do
    struct(
      Pristine.OAuth2.Provider,
      Keyword.merge(
        [
          name: "example",
          flow: :authorization_code,
          site: "https://api.example.com",
          authorize_url: "/oauth/authorize",
          token_url: "/oauth/token",
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

  defp string_input(contents) do
    {:ok, device} = StringIO.open(contents)
    device
  end

  defp string_output do
    {:ok, device} = StringIO.open("")
    device
  end

  test "accepts a full redirect url pasted manually" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert Jason.decode!(request.body) == %{
               "code" => "auth-code",
               "grant_type" => "authorization_code",
               "redirect_uri" => "https://example.com/callback"
             }

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body: ~s({"access_token":"secret_access","token_type":"bearer"})
       }}
    end)

    output = string_output()

    assert {:ok, %OAuth2.Token{access_token: "secret_access"}} =
             Interactive.authorize(provider(),
               browser: FakeBrowser,
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context(),
               input:
                 string_input("https://example.com/callback?code=auth-code&state=state-123\n"),
               manual?: true,
               open_browser?: false,
               output: output,
               redirect_uri: "https://example.com/callback",
               state: "state-123"
             )

    {_input, written} = StringIO.contents(output)
    assert written =~ "Open this URL to authorize:"
    assert written =~ "Paste the full redirect URL or the raw authorization code."
  end

  test "accepts a raw authorization code pasted manually" do
    expect(Pristine.TransportMock, :send, fn %Request{} = request, %Context{} ->
      assert Jason.decode!(request.body)["code"] == "auth-code"

      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body: ~s({"access_token":"secret_access","token_type":"bearer"})
       }}
    end)

    assert {:ok, %OAuth2.Token{access_token: "secret_access"}} =
             Interactive.authorize(provider(),
               browser: FakeBrowser,
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context(),
               input: string_input("auth-code\n"),
               manual?: true,
               open_browser?: false,
               output: string_output(),
               redirect_uri: "https://example.com/callback"
             )
  end

  test "rejects state mismatches when the full redirect url is pasted" do
    assert {:error, %Error{reason: :authorization_state_mismatch}} =
             Interactive.authorize(provider(),
               browser: FakeBrowser,
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context(),
               input:
                 string_input("https://example.com/callback?code=auth-code&state=wrong-state\n"),
               manual?: true,
               open_browser?: false,
               output: string_output(),
               redirect_uri: "https://example.com/callback",
               state: "expected-state"
             )
  end

  test "returns callback errors without falling back to manual input" do
    Process.put(
      :callback_server_result,
      {:error,
       Error.new(
         :authorization_callback_error,
         message: "authorization callback returned error :access_denied"
       )}
    )

    output = string_output()

    assert {:error, %Error{reason: :authorization_callback_error}} =
             Interactive.authorize(provider(),
               browser: FakeBrowser,
               callback_server: FakeCallbackServer,
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context(),
               input: string_input("unused\n"),
               open_browser?: false,
               output: output,
               redirect_uri: "http://127.0.0.1:40071/callback"
             )

    assert_receive {:callback_server_start, "http://127.0.0.1:40071/callback", _opts}

    assert_receive {:callback_server_await, %{redirect_uri: "http://127.0.0.1:40071/callback"},
                    120_000}

    assert_receive {:callback_server_stop, %{redirect_uri: "http://127.0.0.1:40071/callback"}}

    {_input, written} = StringIO.contents(output)
    refute written =~ "Paste the full redirect URL"
  after
    Process.delete(:callback_server_result)
  end

  test "falls back cleanly when opening the browser fails" do
    Process.put(:browser_result, {:error, {:command_failed, "xdg-open", 1, "boom"}})

    expect(Pristine.TransportMock, :send, fn %Request{}, %Context{} ->
      {:ok,
       %Response{
         status: 200,
         headers: %{"content-type" => "application/json"},
         body: ~s({"access_token":"secret_access","token_type":"bearer"})
       }}
    end)

    output = string_output()

    assert {:ok, %OAuth2.Token{access_token: "secret_access"}} =
             Interactive.authorize(provider(),
               browser: FakeBrowser,
               client_id: "client-id",
               client_secret: "client-secret",
               context: oauth_context(),
               input: string_input("auth-code\n"),
               manual?: true,
               output: output,
               redirect_uri: "https://example.com/callback"
             )

    assert_receive {:browser_open, url}
    assert url =~ "https://api.example.com/oauth/authorize"

    {_input, written} = StringIO.contents(output)
    assert written =~ "Browser open failed:"
  after
    Process.delete(:browser_result)
  end
end
