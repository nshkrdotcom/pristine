defmodule Pristine.Core.PipelineRuntimeSeamsTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Adapters.Auth.{Basic, Bearer}
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

  defmodule OpenAPIRequest do
    def __schema__(type \\ :t)

    def __schema__(:t) do
      Sinter.Schema.define([
        {:prompt, :string, required: true},
        {:count, :integer, optional: true}
      ])
    end

    def decode(data, type \\ :t) do
      Sinter.Validator.validate(__schema__(type), data)
    end
  end

  defmodule OpenAPIProfile do
    defstruct [:city, :created_at]

    def __schema__(type \\ :t)

    def __schema__(:t) do
      Sinter.Schema.define([
        {:city, :string, required: true},
        {:created_at, :datetime, required: true}
      ])
    end

    def decode(data, type \\ :t) do
      with {:ok, validated} <- Sinter.Validator.validate(__schema__(type), data),
           {:ok, created_at, _offset} <- DateTime.from_iso8601(validated["created_at"]) do
        {:ok,
         %__MODULE__{
           city: validated["city"],
           created_at: created_at
         }}
      end
    end
  end

  defmodule OpenAPIResponse do
    defstruct [:id, :object, :profile, :tags]

    def __schema__(type \\ :t)

    def __schema__(:t) do
      Sinter.Schema.define([
        {:id, :uuid, required: true},
        {:object, {:literal, "user"}, required: true},
        {:profile, {:object, OpenAPIProfile.__schema__(:t)}, required: true},
        {:tags, {:array, :string}, optional: true}
      ])
    end

    def decode(data, type \\ :t) do
      with {:ok, validated} <- Sinter.Validator.validate(__schema__(type), data),
           {:ok, profile} <- OpenAPIProfile.decode(validated["profile"]) do
        {:ok,
         %__MODULE__{
           id: validated["id"],
           object: validated["object"],
           profile: profile,
           tags: validated["tags"]
         }}
      end
    end
  end

  defmodule OpenAPILiteralFlag do
    alias Pristine.OpenAPI.Runtime, as: OpenAPIRuntime

    def __openapi_fields__(:t) do
      [
        %{
          default: nil,
          name: "type",
          nullable: false,
          required: true,
          type: {:const, "workspace"}
        },
        %{default: nil, name: "workspace", nullable: false, required: true, type: {:const, true}}
      ]
    end

    def __schema__(:t) do
      OpenAPIRuntime.build_schema(__openapi_fields__(:t))
    end

    def decode(data, type \\ :t) do
      OpenAPIRuntime.decode_module_type(__MODULE__, type, data)
    end
  end

  defmodule TestHTTPClassifier do
    alias Foundation.Retry.HTTP
    alias Pristine.Core.Response

    def classify({:ok, %Response{status: 429, headers: headers}}, _endpoint, _context, _opts) do
      retry_after_ms = HTTP.parse_retry_after(headers)

      %{
        retry?: true,
        retry_after_ms: retry_after_ms,
        limiter_backoff_ms: retry_after_ms,
        breaker_outcome: :ignore,
        telemetry: %{classification: :rate_limited, breaker_outcome: :ignore}
      }
    end

    def classify({:ok, %Response{status: status}}, _endpoint, _context, _opts)
        when status in [408, 500, 502, 503, 504] do
      %{
        retry?: true,
        retry_after_ms: nil,
        limiter_backoff_ms: nil,
        breaker_outcome: :failure,
        telemetry: %{classification: :upstream_failure, breaker_outcome: :failure}
      }
    end

    def classify({:ok, %Response{status: status}}, _endpoint, _context, _opts)
        when status >= 200 and status < 300 do
      %{
        retry?: false,
        retry_after_ms: nil,
        limiter_backoff_ms: nil,
        breaker_outcome: :success,
        telemetry: %{classification: :success, breaker_outcome: :success}
      }
    end

    def classify({:error, reason}, _endpoint, _context, _opts) do
      %{
        retry?: true,
        retry_after_ms: nil,
        limiter_backoff_ms: nil,
        breaker_outcome: :failure,
        telemetry: %{classification: :transport_error, reason: inspect(reason)}
      }
    end

    def classify(_result, _endpoint, _context, _opts) do
      %{
        retry?: false,
        retry_after_ms: nil,
        limiter_backoff_ms: nil,
        breaker_outcome: :ignore,
        telemetry: %{classification: :ignored, breaker_outcome: :ignore}
      }
    end
  end

  defmodule TrackingRateLimiter do
    @behaviour Pristine.Ports.RateLimit

    @impl true
    def within_limit(fun, opts) when is_function(fun, 0) do
      send(test_pid(opts), {:rate_limit_within_limit, opts})
      fun.()
    end

    @impl true
    def for_key(key, opts \\ []) do
      limiter = {:limiter, key}
      send(test_pid(opts), {:rate_limit_for_key, key, opts})
      limiter
    end

    @impl true
    def wait(limiter, opts \\ []) do
      send(test_pid(opts), {:rate_limit_wait, limiter, opts})
      :ok
    end

    @impl true
    def clear(limiter) do
      send(self(), {:rate_limit_clear, limiter})
      :ok
    end

    @impl true
    def set(limiter, duration_ms, opts \\ []) do
      send(test_pid(opts), {:rate_limit_set, limiter, duration_ms, opts})
      :ok
    end

    defp test_pid(opts), do: Keyword.fetch!(opts, :test_pid)
  end

  defmodule TrackingAdmissionControl do
    @behaviour Pristine.Ports.AdmissionControl

    @impl true
    def with_admission(fun, opts) when is_function(fun, 0) do
      send(test_pid(opts), {:admission_enter, opts})
      fun.()
    end

    @impl true
    def set_backoff(duration_ms, opts) do
      send(test_pid(opts), {:admission_backoff, duration_ms, opts})
      :ok
    end

    defp test_pid(opts), do: Keyword.fetch!(opts, :test_pid)
  end

  defmodule TrackingRetryAdapter do
    @behaviour Pristine.Ports.Retry

    @impl true
    def with_retry(fun, opts) when is_function(fun, 0) do
      before_attempt = Keyword.get(opts, :before_attempt, fn _attempt -> :ok end)
      before_attempt.(0)
      first_result = fun.()

      case Keyword.fetch!(opts, :policy) do
        %{retry_on: retry_on, retry_after_ms_fun: retry_after_ms_fun} ->
          retry_after_ms_fun.(first_result)

          if retry_on.(first_result) do
            before_attempt.(1)
            fun.()
          else
            first_result
          end

        _other ->
          first_result
      end
    end

    @impl true
    def build_policy(opts \\ []) do
      %{
        retry_on: Keyword.fetch!(opts, :retry_on),
        retry_after_ms_fun: Keyword.fetch!(opts, :retry_after_ms_fun)
      }
    end

    @impl true
    def build_backoff(opts \\ []), do: opts
  end

  test "supports request-level bearer auth override" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context = runtime_context(auth: [Bearer.new("default-token")])

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

    context = runtime_context(auth: [Bearer.new("default-token")])
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

  test "resolves scheme-scoped auth from endpoint security metadata" do
    manifest = runtime_manifest(security: [%{bearerAuth: []}])
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        auth: %{
          "bearerAuth" => [Bearer.new("scheme-token")],
          "basicAuth" => [Basic.new("client-id", "client-secret")]
        }
      )

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      assert headers["Authorization"] == "Bearer scheme-token"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)
  end

  test "request-level auth overrides still win over security metadata" do
    manifest = runtime_manifest(security: [%{bearerAuth: []}])
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        auth: %{
          "bearerAuth" => [Bearer.new("scheme-token")]
        }
      )

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      assert headers["Authorization"] == "Bearer override-token"
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} =
             Pipeline.execute(manifest, "ping", payload, context, auth: "override-token")
  end

  test "endpoint security empty list disables inherited manifest security" do
    manifest =
      runtime_manifest(
        [security: []],
        %{
          security: [%{bearerAuth: []}]
        }
      )

    payload = %{"prompt" => "hi"}
    context = runtime_context(auth: [Bearer.new("default-token")])

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      refute Map.has_key?(headers, "Authorization")
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)
  end

  test "does not fall back to legacy endpoint auth lookup when no security metadata is present" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        auth: %{
          "basicAuth" => [Basic.new("client-id", "client-secret")]
        }
      )

    expect_runtime_success(payload, fn %Request{headers: headers}, _context ->
      refute Map.has_key?(headers, "Authorization")
      {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)
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
    manifest = runtime_manifest(security: [%{bearerAuth: []}])
    payload = %{"prompt" => "hi"}

    logger = fn level, message, meta ->
      send(self(), {:log, level, message, meta})
      :ok
    end

    context =
      runtime_context(
        auth: [Bearer.new("secret-token")],
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

    expect(Pristine.RateLimitMock, :for_key, fn :default, [] ->
      :default_limiter
    end)

    expect(Pristine.RateLimitMock, :set, fn :default_limiter, 7_000, [] ->
      :ok
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

  test "learns shared limiter backoff from classified 429 responses" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        retry: Pristine.Adapters.Retry.Noop,
        rate_limiter: TrackingRateLimiter,
        rate_limit_opts: [key: {:integration, :demo}, test_pid: self()],
        result_classifier: TestHTTPClassifier
      )

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
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

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error,
            %Pristine.Error{
              status: 429,
              body: %{"code" => "rate_limited", "message" => "Slow down"}
            }} = Pipeline.execute(manifest, "ping", payload, context)

    assert_received {:rate_limit_for_key, {:integration, :demo}, _opts}

    assert_received {:rate_limit_set, {:limiter, {:integration, :demo}}, 7_000, opts}
    assert Keyword.get(opts, :key) == {:integration, :demo}
  end

  test "counts classified HTTP failures against the circuit breaker" do
    manifest = runtime_manifest()
    payload = %{"prompt" => "hi"}
    registry = Foundation.CircuitBreaker.Registry.new_registry()

    context =
      runtime_context(
        retry: Pristine.Adapters.Retry.Noop,
        rate_limiter: Pristine.Adapters.RateLimit.Noop,
        circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
        circuit_breaker_opts: [
          registry: registry,
          failure_threshold: 1,
          reset_timeout_ms: 60_000
        ],
        result_classifier: TestHTTPClassifier
      )

    expect(Pristine.SerializerMock, :encode, 2, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 503,
         body: "{\"code\":\"service_unavailable\",\"message\":\"Later\"}"
       }}
    end)

    expect(
      Pristine.SerializerMock,
      :decode,
      fn "{\"code\":\"service_unavailable\",\"message\":\"Later\"}", nil, _opts ->
        {:ok, %{"code" => "service_unavailable", "message" => "Later"}}
      end
    )

    expect(Pristine.TelemetryMock, :emit, 4, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error,
            %Pristine.Error{
              status: 503,
              body: %{"code" => "service_unavailable", "message" => "Later"}
            }} = Pipeline.execute(manifest, "ping", payload, context)

    assert {:error, :circuit_open} = Pipeline.execute(manifest, "ping", payload, context)
  end

  test "wraps requests in admission control and propagates classified backoff" do
    manifest = runtime_manifest(resource: "core_api")
    payload = %{"prompt" => "hi"}

    context =
      runtime_context(
        retry: Pristine.Adapters.Retry.Noop,
        admission_control: TrackingAdmissionControl,
        admission_opts: [test_pid: self()],
        rate_limiter: Pristine.Adapters.RateLimit.Noop,
        result_classifier: TestHTTPClassifier
      )

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
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

    assert {:error, %Pristine.Error{status: 429}} =
             Pipeline.execute(manifest, "ping", payload, context)

    assert_received {:admission_enter, opts}
    assert opts[:resource] == "core_api"
    assert is_integer(opts[:estimated_bytes])
    assert opts[:estimated_bytes] > 0

    assert_received {:admission_backoff, 7_000, backoff_opts}
    assert backoff_opts[:resource] == "core_api"
  end

  test "classifies each attempt once and reuses the outcome across resilience seams" do
    manifest = runtime_manifest(resource: "core_api")
    payload = %{"prompt" => "hi"}
    parent = self()
    breaker_registry = Foundation.CircuitBreaker.Registry.new_registry()

    classifier = fn result, endpoint, context, opts ->
      send(parent, {:classification_call, result})
      TestHTTPClassifier.classify(result, endpoint, context, opts)
    end

    context =
      runtime_context(
        retry: TrackingRetryAdapter,
        retry_opts: [
          max_retries: 1,
          base_delay_ms: 1,
          max_delay_ms: 1
        ],
        rate_limiter: TrackingRateLimiter,
        rate_limit_opts: [key: {:integration, :demo}, test_pid: self()],
        circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
        circuit_breaker_opts: [
          registry: breaker_registry,
          failure_threshold: 5,
          reset_timeout_ms: 60_000
        ],
        admission_control: TrackingAdmissionControl,
        admission_opts: [test_pid: self()],
        result_classifier: classifier
      )

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.TransportMock, :send, 2, fn %Request{}, _context ->
      attempt = Process.get(:classification_attempt, 0)
      Process.put(:classification_attempt, attempt + 1)

      case attempt do
        0 ->
          {:ok,
           %Response{
             status: 429,
             headers: %{"retry-after" => "0"},
             body: "{\"code\":\"rate_limited\",\"message\":\"Slow down\"}"
           }}

        _ ->
          {:ok, %Response{status: 200, body: "{\"ok\":true}"}}
      end
    end)

    expect(
      Pristine.SerializerMock,
      :decode,
      fn body, _schema, _opts ->
        case body do
          "{\"code\":\"rate_limited\",\"message\":\"Slow down\"}" ->
            {:ok, %{"code" => "rate_limited", "message" => "Slow down"}}

          "{\"ok\":true}" ->
            {:ok, %{"ok" => true}}
        end
      end
    )

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"ok" => true}} = Pipeline.execute(manifest, "ping", payload, context)

    assert_received {:classification_call, {:ok, %Response{status: 429}}}
    assert_received {:classification_call, {:ok, %Response{status: 200}}}
    refute_receive {:classification_call, _result}
  end

  test "validates request payloads from direct OpenAPI schema refs" do
    manifest = openapi_manifest(request: {OpenAPIRequest, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error, [%Sinter.Error{code: :required, path: ["prompt"]}]} =
             Pipeline.execute(manifest, "ping", %{"count" => 2}, context)
  end

  test "fails fast when a direct OpenAPI schema ref points at an unavailable module" do
    missing_module = Module.concat(__MODULE__, MissingOpenAPIType)
    manifest = openapi_manifest(response: {missing_module, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    assert_raise ArgumentError,
                 ~r/module #{Regex.escape(inspect(missing_module))} is not available/,
                 fn ->
                   Pipeline.execute(manifest, "ping", %{"prompt" => "hi"}, context)
                 end
  end

  test "validates success responses from direct OpenAPI schema refs" do
    manifest = openapi_manifest(response: {OpenAPIResponse, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 200,
         body:
           ~s({"object":"user","profile":{"city":"Honolulu","created_at":"2026-03-10T00:00:00Z"}})
       }}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:error, [%Sinter.Error{code: :required, path: ["id"]}]} =
             Pipeline.execute(manifest, "ping", %{"prompt" => "hi"}, context)
  end

  test "returns validated maps by default for direct OpenAPI schema refs" do
    manifest = openapi_manifest(response: {OpenAPIResponse, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 200,
         body:
           ~s({"id":"01234567-89ab-cdef-0123-456789abcdef","object":"user","profile":{"city":"Honolulu","created_at":"2026-03-10T00:00:00Z"},"tags":["alpha","beta"]})
       }}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok,
            %{
              "id" => "01234567-89ab-cdef-0123-456789abcdef",
              "object" => "user",
              "profile" => %{
                "city" => "Honolulu",
                "created_at" => "2026-03-10T00:00:00Z"
              },
              "tags" => ["alpha", "beta"]
            }} = Pipeline.execute(manifest, "ping", %{"prompt" => "hi"}, context)
  end

  test "builds schemas for generated literal boolean OpenAPI fields" do
    assert {:ok, %{type: "workspace", workspace: true}} =
             OpenAPILiteralFlag.decode(%{"type" => "workspace", "workspace" => true})
  end

  test "materializes typed OpenAPI responses when opted in" do
    manifest = openapi_manifest(response: {OpenAPIResponse, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 200,
         body:
           ~s({"id":"01234567-89ab-cdef-0123-456789abcdef","object":"user","profile":{"city":"Honolulu","created_at":"2026-03-10T00:00:00Z"},"tags":["alpha","beta"]})
       }}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %OpenAPIResponse{} = response} =
             Pipeline.execute(manifest, "ping", %{"prompt" => "hi"}, context,
               typed_responses: true
             )

    assert %OpenAPIProfile{} = response.profile
    assert response.profile.city == "Honolulu"
    assert %DateTime{} = response.profile.created_at
  end

  test "materializes typed OpenAPI map responses when opted in" do
    manifest = openapi_manifest(response: {OpenAPILiteralFlag, :t})
    context = runtime_context(serializer: Pristine.Adapters.Serializer.JSON)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "ping", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{}, _context ->
      {:ok,
       %Response{
         status: 200,
         body: ~s({"type":"workspace","workspace":true})
       }}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{type: "workspace", workspace: true}} =
             Pipeline.execute(manifest, "ping", %{"prompt" => "hi"}, context,
               typed_responses: true
             )
  end

  defp runtime_manifest(overrides \\ [], manifest_overrides \\ %{}) do
    manifest =
      %{
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
      |> Map.merge(manifest_overrides)

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

  defp openapi_manifest(overrides) do
    endpoint =
      %{
        id: "ping",
        method: "POST",
        path: "/ping",
        request: {OpenAPIRequest, :t},
        response: {OpenAPIResponse, :t}
      }
      |> Map.merge(Enum.into(overrides, %{}))

    %Manifest{
      name: "openapi-demo",
      version: "0.1.0",
      endpoints: %{"ping" => struct(Manifest.Endpoint, endpoint)},
      types: %{}
    }
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
