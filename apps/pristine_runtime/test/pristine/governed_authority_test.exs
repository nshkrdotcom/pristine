defmodule Pristine.GovernedAuthorityTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Adapters.Auth.Bearer
  alias Pristine.Adapters.TokenSource.File
  alias Pristine.Core.{Context, EndpointMetadata, Pipeline, Request, Response}
  alias Pristine.OAuth2
  alias Pristine.OAuth2.{Provider, SavedToken}

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "governed context materializes authority-selected base url and credential headers" do
    context = governed_context()

    expect_successful_pipeline(context, fn %Request{url: url, headers: headers} ->
      assert url == "https://governed.example.test/v1/widgets"
      assert headers["Authorization"] == "Bearer governed-token"
      assert headers["X-Governed-Target"] == "target-123"
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), %{"ok" => true}, context)
  end

  test "governed context rejects direct base url, headers, auth, and extra headers" do
    direct_values = [
      base_url: "https://env.example.test",
      headers: %{"Authorization" => "Bearer env-token"},
      auth: [Bearer.new("env-token")],
      default_headers: %{"Authorization" => "Bearer env-token"},
      default_auth: [Bearer.new("env-token")],
      extra_headers: fn _endpoint, _context, _opts -> %{"X-Env" => "env-value"} end
    ]

    for {key, value} <- direct_values do
      error =
        assert_raise ArgumentError, fn ->
          Context.new([{key, value}, {:governed_authority, authority()}])
        end

      assert String.contains?(error.message, "governed authority")
    end
  end

  test "governed requests reject request headers and auth overrides" do
    context = governed_context()

    header_error =
      assert_raise ArgumentError, fn ->
        Pipeline.build_request(
          endpoint(),
          nil,
          nil,
          context,
          headers: %{"Authorization" => "Bearer env-token"}
        )
      end

    assert String.contains?(header_error.message, "governed authority")

    auth_error =
      assert_raise ArgumentError, fn ->
        Pipeline.build_request(endpoint(), nil, nil, context, auth: [Bearer.new("env-token")])
      end

    assert String.contains?(auth_error.message, "governed authority")
  end

  test "governed endpoint metadata rejects auth-sensitive direct headers" do
    context = governed_context()

    error =
      assert_raise ArgumentError, fn ->
        endpoint()
        |> Map.put(:headers, %{"Authorization" => "Bearer env-token"})
        |> Pipeline.build_request(nil, nil, context, [])
      end

    assert String.contains?(error.message, "governed authority")
  end

  test "governed saved-token refresh rejects file token sources before file reads" do
    context = governed_context()

    assert {:error, :governed_oauth_token_source_forbidden} =
             SavedToken.refresh(
               provider(),
               context: context,
               token_source: {File, path: "/tmp/pristine-env-token.json"},
               client_id: "client-id",
               client_secret: "client-secret"
             )
  end

  test "governed OAuth token requests reject direct OAuth client secrets" do
    context = governed_context()

    assert {:error, %OAuth2.Error{reason: :governed_oauth_request_forbidden}} =
             OAuth2.exchange_code(
               provider(),
               "auth-code",
               context: context,
               client_id: "client-id",
               client_secret: "client-secret"
             )
  end

  test "governed header dumps redact authority credential headers" do
    test_pid = self()

    context =
      governed_context(
        dump_headers?: true,
        log_level: :debug,
        logger: fn level, message, metadata ->
          send(test_pid, {:log, level, message, metadata})
        end
      )

    expect_successful_pipeline(context, fn %Request{headers: headers} ->
      assert headers["Authorization"] == "Bearer governed-token"
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), %{"ok" => true}, context)

    assert_receive {:log, :debug, "request attempt", %{headers: headers}}
    assert headers["Authorization"] == "[REDACTED]"

    refute String.contains?(inspect(headers), "governed-token")
  end

  test "standalone direct bearer auth remains compatible" do
    context =
      %Context{
        base_url: "https://standalone.example.test",
        auth: [Bearer.new("standalone-token")],
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock
      }

    expect_successful_pipeline(context, fn %Request{url: url, headers: headers} ->
      assert url == "https://standalone.example.test/v1/widgets"
      assert headers["Authorization"] == "Bearer standalone-token"
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), %{"ok" => true}, context)
  end

  defp expect_successful_pipeline(context, request_assertions) do
    expect(Pristine.SerializerMock, :encode, fn %{"ok" => true}, _opts ->
      {:ok, "{\"ok\":true}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "widgets.list", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{} = request, ^context ->
      request_assertions.(request)
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"ok\":true}", _schema, _opts ->
      {:ok, %{"ok" => true}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)
  end

  defp governed_context(overrides \\ []) do
    Context.new(
      Keyword.merge(
        [
          governed_authority: authority(),
          transport: Pristine.TransportMock,
          serializer: Pristine.SerializerMock,
          retry: Pristine.RetryMock,
          telemetry: Pristine.TelemetryMock,
          circuit_breaker: Pristine.CircuitBreakerMock,
          rate_limiter: Pristine.RateLimitMock
        ],
        overrides
      )
    )
  end

  defp authority do
    [
      base_url: "https://governed.example.test",
      credential_ref: "credential-123",
      credential_lease_ref: "lease-123",
      target_ref: "target-123",
      redaction_ref: "redaction-123",
      headers: %{"X-Governed-Target" => "target-123"},
      credential_headers: %{"Authorization" => "Bearer governed-token"}
    ]
  end

  defp endpoint do
    %EndpointMetadata{
      id: "widgets.list",
      method: "POST",
      path: "/v1/widgets",
      headers: %{},
      query: %{},
      security: [%{"bearerAuth" => []}]
    }
  end

  defp provider do
    %Provider{
      name: "example",
      site: "https://governed.example.test",
      flow: :authorization_code,
      token_url: "/oauth/token",
      client_auth_method: :basic
    }
  end
end
