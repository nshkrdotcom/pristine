defmodule Pristine.GovernedAuthorityTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Adapters.Auth.Bearer
  alias Pristine.Adapters.TokenSource.File
  alias Pristine.Core.{Context, EndpointMetadata, Pipeline, Request, Response}
  alias Pristine.GovernedAuthority
  alias Pristine.OAuth2
  alias Pristine.OAuth2.{Provider, SavedToken}

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "governed authority requires credential-handle and request materialization refs" do
    authority =
      GovernedAuthority.new!(
        phase6_authority(
          materialization_kind: "oauth-token-source",
          oauth_token_source_ref: "oauth-token-source://tenant-1/pristine/notion"
        )
      )

    assert authority.credential_handle_ref == "credential-handle://tenant-1/pristine/notion"
    assert authority.credential_lease_ref == "credential-lease://tenant-1/pristine/notion"
    assert authority.request_scope_ref == "request-scope://tenant-1/pristine/notion/list"
    assert authority.base_url_ref == "base-url://tenant-1/pristine/notion"
    assert authority.header_policy_ref == "header-policy://tenant-1/pristine/notion"
    assert authority.materialization_kind == "oauth_token_source"
    assert authority.oauth_token_source_ref == "oauth-token-source://tenant-1/pristine/notion"
  end

  test "governed authority supports app, installation, and user token materialization refs" do
    cases = [
      {"app-token", :app_token_ref, "app-token://tenant-1/pristine/app"},
      {
        "installation-token",
        :installation_token_ref,
        "installation-token://tenant-1/pristine/install"
      },
      {"user-token", :user_token_ref, "user-token://tenant-1/pristine/user"}
    ]

    for {kind, ref_field, ref} <- cases do
      authority =
        phase6_authority([
          {:materialization_kind, kind},
          {:bearer_token_ref, nil},
          {ref_field, ref}
        ])
        |> GovernedAuthority.new!()

      assert Map.fetch!(authority, ref_field) == ref
    end
  end

  test "governed authority rejects standalone evidence and unmanaged auth inputs" do
    unmanaged_inputs = [
      bearer: "raw-bearer-token",
      api_key: "raw-api-key",
      env: %{"API_TOKEN" => "raw-env-token"},
      token_file: "/tmp/pristine-token.json",
      default_client: :provider_default_client,
      middleware: fn request -> request end,
      oauth_token_source: {File, path: "/tmp/pristine-token.json"}
    ]

    for {key, value} <- unmanaged_inputs do
      error =
        assert_raise ArgumentError, fn ->
          phase6_authority([{key, value}])
          |> GovernedAuthority.new!()
        end

      assert String.contains?(error.message, "governed authority rejects unmanaged #{key}")
    end
  end

  test "governed request options reject unmanaged auth materialization inputs" do
    context = governed_context()

    rejected_options = [
      middleware: fn request -> request end,
      token_source: {File, path: "/tmp/pristine-token.json"},
      oauth_token_source: {File, path: "/tmp/pristine-token.json"},
      api_key: "raw-api-key",
      bearer: "raw-bearer-token",
      token_file: "/tmp/pristine-token.json",
      default_client: :provider_default_client
    ]

    for {key, value} <- rejected_options do
      error =
        assert_raise ArgumentError, fn ->
          Pipeline.build_request(endpoint(), nil, nil, context, [{key, value}])
        end

      assert String.contains?(error.message, "governed authority")
    end
  end

  test "governed authority inspection redacts materialized credential headers" do
    authority =
      phase6_authority(
        credential_headers: %{
          "Authorization" => "Bearer crash-secret",
          "X-Installation-Token" => "install-secret"
        },
        allowed_header_names: ["Authorization", "X-Governed-Target", "X-Installation-Token"]
      )
      |> GovernedAuthority.new!()

    rendered = inspect(authority)

    refute String.contains?(rendered, "crash-secret")
    refute String.contains?(rendered, "install-secret")
    assert String.contains?(rendered, "[REDACTED]")
  end

  test "multiple governed HTTP identities materialize concurrently through distinct refs" do
    first =
      governed_context(
        governed_authority:
          phase6_authority(
            credential_handle_ref: "credential-handle://tenant-1/pristine/notion-a",
            credential_lease_ref: "credential-lease://tenant-1/pristine/notion-a",
            request_scope_ref: "request-scope://tenant-1/pristine/notion-a/list",
            target_ref: "target://tenant-1/pristine/notion-a",
            credential_headers: %{"Authorization" => "Bearer governed-token-a"}
          )
      )

    second =
      governed_context(
        governed_authority:
          phase6_authority(
            credential_handle_ref: "credential-handle://tenant-1/pristine/notion-b",
            credential_lease_ref: "credential-lease://tenant-1/pristine/notion-b",
            request_scope_ref: "request-scope://tenant-1/pristine/notion-b/list",
            target_ref: "target://tenant-1/pristine/notion-b",
            credential_headers: %{"Authorization" => "Bearer governed-token-b"}
          )
      )

    expect_successful_pipeline(first, fn %Request{headers: headers} ->
      assert headers["Authorization"] == "Bearer governed-token-a"
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), %{"ok" => true}, first)

    expect_successful_pipeline(second, fn %Request{headers: headers} ->
      assert headers["Authorization"] == "Bearer governed-token-b"
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute_endpoint(endpoint(), %{"ok" => true}, second)
  end

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
    phase6_authority()
  end

  defp phase6_authority(overrides \\ []) do
    [
      base_url: "https://governed.example.test",
      base_url_ref: "base-url://tenant-1/pristine/notion",
      credential_handle_ref: "credential-handle://tenant-1/pristine/notion",
      credential_lease_ref: "credential-lease://tenant-1/pristine/notion",
      target_ref: "target://tenant-1/pristine/notion",
      request_scope_ref: "request-scope://tenant-1/pristine/notion/list",
      header_policy_ref: "header-policy://tenant-1/pristine/notion",
      materialization_kind: "bearer",
      bearer_token_ref: "bearer-token://tenant-1/pristine/notion",
      redaction_ref: "redaction://tenant-1/pristine/notion",
      headers: %{"X-Governed-Target" => "target-123"},
      credential_headers: %{"Authorization" => "Bearer governed-token"},
      allowed_header_names: ["Authorization", "X-Governed-Target"]
    ]
    |> Keyword.merge(overrides)
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
