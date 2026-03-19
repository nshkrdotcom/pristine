defmodule Pristine.OAuth2.CallbackServerTest do
  use ExUnit.Case, async: false

  @socket_skip (case :gen_tcp.listen(0, [
                       :binary,
                       active: false,
                       ip: {127, 0, 0, 1},
                       reuseaddr: true
                     ]) do
                  {:ok, socket} ->
                    :gen_tcp.close(socket)
                    nil

                  {:error, reason} ->
                    "loopback sockets unavailable in this environment: #{inspect(reason)}"
                end)

  alias Pristine.OAuth2.CallbackServer
  alias Pristine.OAuth2.Error

  setup_all do
    :inets.start()
    :ssl.start()
    :ok
  end

  @tag skip: @socket_skip
  test "captures an authorization callback on the exact loopback redirect uri" do
    port = free_port()
    redirect_uri = "http://127.0.0.1:#{port}/callback"

    assert {:ok, server} = CallbackServer.start(redirect_uri)

    assert {:ok, {{_version, 200, _reason}, _headers, body}} =
             http_get("#{redirect_uri}?code=auth-code&state=state-123")

    assert to_string(body) =~ "OAuth complete"

    assert {:ok, %{code: "auth-code", request_uri: request_uri, state: "state-123"}} =
             CallbackServer.await(server, 1_000)

    assert request_uri == "#{redirect_uri}?code=auth-code&state=state-123"
  end

  @tag skip: @socket_skip
  test "surfaces callback errors returned by the provider" do
    port = free_port()
    redirect_uri = "http://127.0.0.1:#{port}/callback"

    assert {:ok, server} = CallbackServer.start(redirect_uri)

    assert {:ok, {{_version, 400, _reason}, _headers, response_body}} =
             http_get("#{redirect_uri}?error=access_denied&error_description=user%20cancelled")

    assert to_string(response_body) =~ "OAuth failed"

    assert {:error, %Error{reason: :authorization_callback_error, body: error_body}} =
             CallbackServer.await(server, 1_000)

    assert error_body["error"] == "access_denied"
    assert error_body["error_description"] == "user cancelled"
  end

  test "rejects localhost loopback redirect uris because the listener must bind exactly" do
    assert {:error, %Error{reason: :loopback_callback_unavailable}} =
             CallbackServer.start("http://localhost:40071/callback")
  end

  test "returns a structured error when optional callback server dependencies are unavailable" do
    assert {:error, %Error{reason: :loopback_callback_unavailable, message: message}} =
             CallbackServer.start("http://127.0.0.1:40071/callback",
               dependencies_available?: false
             )

    assert message =~ "requires optional"
  end

  defp free_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  defp http_get(url, attempts \\ 10)

  defp http_get(url, attempts) when attempts > 0 do
    case :httpc.request(String.to_charlist(url)) do
      {:error, {:failed_connect, _reasons}} ->
        Process.sleep(10)
        http_get(url, attempts - 1)

      other ->
        other
    end
  end

  defp http_get(url, 0), do: :httpc.request(String.to_charlist(url))
end
