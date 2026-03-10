defmodule Pristine.Core.PipelineRuntimeSeamsTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, Pipeline, Request, Response}
  alias Pristine.Manifest

  setup :set_mox_from_context
  setup :verify_on_exit!

  defmodule ErrorHookModule do
    defexception [:message, :status, :body, :retry_after_ms, :opts]

    def from_response(response, body, retry_after_ms, opts) do
      %__MODULE__{
        message: "mapped",
        status: response.status,
        body: body,
        retry_after_ms: retry_after_ms,
        opts: opts
      }
    end
  end

  test "supports request-level bearer auth override" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context = runtime_context(auth: [Pristine.Adapters.Auth.Bearer.new("default-token")])

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      assert headers["Authorization"] == "Bearer override-token"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute(manifest, "ping", payload, context, auth: "override-token")
  end

  test "supports request-level basic auth override" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context = runtime_context(auth: [Pristine.Adapters.Auth.Bearer.new("default-token")])
    expected = "Basic " <> Base.encode64("client-id:client-secret")

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      assert headers["Authorization"] == expected
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute(manifest, "ping", payload, context,
               auth: %{client_id: "client-id", client_secret: "client-secret"}
             )
  end

  test "rejects raw path traversal in path params before transport" do
    manifest = runtime_manifest(path: "/items/{id}")
    payload = %{"prompt" => "hi"}
    context = runtime_context()

    expect_encode_only(payload)
    expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

    assert_raise ArgumentError, ~r/path traversal/i, fn ->
      Pipeline.execute(manifest, "ping", payload, context, path_params: %{id: "../secret"})
    end
  end

  test "rejects encoded path traversal in path overrides before transport" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}
    context = runtime_context()

    expect_encode_only(payload)
    expect(Pristine.RetryMock, :with_retry, fn fun, _opts -> fun.() end)
    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas -> :ok end)

    assert_raise ArgumentError, ~r/path traversal/i, fn ->
      Pipeline.execute(manifest, "ping", payload, context, path: "/safe/%2e%2e/secret")
    end
  end

  test "emits structured logger callbacks with redacted request dumps" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    logger = fn level, message, meta ->
      send(self(), {:log, level, message, meta})
      :ok
    end

    context =
      runtime_context(
        auth: [Pristine.Adapters.Auth.Bearer.new("secret-token")],
        logger: logger,
        log_level: :debug,
        dump_headers?: true
      )

    expect_runtime_success(payload, fn %Request{}, _context ->
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)

    assert_receive {:log, :info, "request start", %{endpoint_id: "ping", path: "/ping"}}

    assert_receive {:log, :debug, "request attempt",
                    %{
                      attempt: 0,
                      endpoint_id: "ping",
                      headers: headers,
                      body: "{\"prompt\":\"hi\"}"
                    }}

    assert headers["Authorization"] == "[REDACTED]"

    assert_receive {:log, :info, "request success",
                    %{endpoint_id: "ping", path: "/ping", status: 200}}
  end

  test "passes response details through error hook modules with retry metadata" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        error_module: ErrorHookModule,
        retry: Pristine.Adapters.Retry.Foundation,
        retry_opts: [max_retries: 0]
      )

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 429,
         headers: %{"retry-after" => "7"},
         body: "{\"code\":\"rate_limited\",\"message\":\"Slow down\"}"
       }}
    end)

    expect(
      Pristine.SerializerMock,
      :decode,
      fn "{\"code\":\"rate_limited\",\"message\":\"Slow down\"}", nil, _opts ->
        {:ok, %{"code" => "rate_limited", "message" => "Slow down"}}
      end
    )

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error,
            %ErrorHookModule{
              status: 429,
              body: %{"code" => "rate_limited", "message" => "Slow down"},
              retry_after_ms: 7_000,
              opts: []
            }} = Pipeline.execute(manifest, "ping", payload, context)
  end

  defp runtime_manifest(overrides \\ []) do
    manifest = %{
      name: "demo",
      version: "0.1.0",
      endpoints: [
        %{
          id: "ping",
          method: "POST",
          path: "/ping",
          request: "PingRequest",
          response: "PingResponse"
        }
      ],
      types: %{
        "PingRequest" => %{fields: %{prompt: %{type: "string", required: true}}},
        "PingResponse" => %{fields: %{ok: %{type: "boolean", required: true}}}
      }
    }

    endpoint_overrides = Enum.into(overrides, %{})

    manifest =
      put_in(
        manifest,
        [:endpoints, Access.at(0)],
        Map.merge(List.first(manifest.endpoints), endpoint_overrides)
      )

    {:ok, loaded} = Manifest.load(manifest)
    loaded
  end

  defp runtime_context(overrides \\ []) do
    base =
      %Context{
        base_url: "https://example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: Pristine.RetryMock,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock
      }

    Enum.reduce(overrides, base, fn {key, value}, context ->
      Map.put(context, key, value)
    end)
  end

  defp expect_runtime_success(payload, transport_fun) do
    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, transport_fun)

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

  defp expect_encode_only(payload) do
    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)
  end
end
