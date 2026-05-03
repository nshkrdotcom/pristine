defmodule Pristine.Core.PipelineTest do
  use ExUnit.Case, async: true
  import Mox

  alias Pristine.Core.{Context, EndpointMetadata, Pipeline, Request, Response}

  setup :set_mox_from_context
  setup :verify_on_exit!

  defmodule HttpPolicyRetryAdapter do
    @behaviour Pristine.Ports.Retry

    @impl true
    def with_retry(fun, opts) when is_function(fun, 0) do
      send(self(), {:with_retry_opts, opts})
      fun.()
    end

    @impl true
    def build_policy(opts) do
      send(self(), {:build_policy_opts, opts})
      :http_retry_policy
    end

    @impl true
    def build_backoff(opts) do
      send(self(), {:build_backoff_opts, opts})
      :normalized_backoff
    end
  end

  test "executes the request pipeline" do
    context = context()
    payload = %{"prompt" => "hi", "sampling_params" => "params"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, method: "POST"}, ^context ->
      assert url == "https://example.com/sampling"
      {:ok, %Response{status: 200, body: "{\"text\":\"hi\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"text\":\"hi\"}", _schema, _opts ->
      {:ok, %{"text" => "hi"}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "sample", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"text" => "hi"}} = Pipeline.execute_endpoint(endpoint(), payload, context)
  end

  test "applies auth, query, and path params" do
    context = context()
    payload = %{"prompt" => "hi", "sampling_params" => "params"}

    expect(Pristine.AuthMock, :headers, fn _opts ->
      {:ok, %{"X-API-Key" => "secret"}}
    end)

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "sample", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, headers: headers}, ^context ->
      assert url == "https://example.com/sampling/abc?limit=10"
      assert headers["X-API-Key"] == "secret"
      {:ok, %Response{status: 200, body: "{\"text\":\"hi\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"text\":\"hi\"}", _schema, _opts ->
      {:ok, %{"text" => "hi"}}
    end)

    expect(Pristine.RetryMock, :with_retry, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"text" => "hi"}} =
             Pipeline.execute_endpoint(
               endpoint(path: "/sampling/{id}"),
               payload,
               context,
               auth: [{Pristine.AuthMock, value: "secret"}],
               path_params: %{id: "abc"},
               query: %{limit: 10}
             )
  end

  test "normalizes retry policies into adapter-ready backoff and policy options" do
    context =
      %Context{
        base_url: "https://example.com",
        transport: Pristine.TransportMock,
        serializer: Pristine.SerializerMock,
        retry: HttpPolicyRetryAdapter,
        telemetry: Pristine.TelemetryMock,
        circuit_breaker: Pristine.CircuitBreakerMock,
        rate_limiter: Pristine.RateLimitMock,
        retry_policies: %{
          "default" => %{
            "max_attempts" => 4,
            "backoff" => "linear",
            "base_ms" => 250,
            "max_ms" => 1_000,
            "jitter" => 0.5,
            "jitter_strategy" => "factor"
          }
        }
      }

    payload = %{"prompt" => "hi", "sampling_params" => "params"}

    expect(Pristine.SerializerMock, :encode, fn ^payload, _opts ->
      {:ok, "{\"prompt\":\"hi\"}"}
    end)

    expect(Pristine.RateLimitMock, :within_limit, fn fun, _opts ->
      fun.()
    end)

    expect(Pristine.CircuitBreakerMock, :call, fn "sample", fun, _opts ->
      fun.()
    end)

    expect(Pristine.TransportMock, :send, fn %Request{url: url, method: "POST"}, ^context ->
      assert url == "https://example.com/sampling"
      {:ok, %Response{status: 200, body: "{\"text\":\"hi\"}"}}
    end)

    expect(Pristine.SerializerMock, :decode, fn "{\"text\":\"hi\"}", _schema, _opts ->
      {:ok, %{"text" => "hi"}}
    end)

    expect(Pristine.TelemetryMock, :emit, 2, fn _event, _meta, _meas ->
      :ok
    end)

    assert {:ok, %{"text" => "hi"}} =
             Pipeline.execute_endpoint(endpoint(retry: "default"), payload, context)

    assert_received {:build_backoff_opts, build_backoff_opts}
    assert Keyword.get(build_backoff_opts, :strategy) == :linear
    assert Keyword.get(build_backoff_opts, :base_ms) == 250
    assert Keyword.get(build_backoff_opts, :max_ms) == 1_000
    assert Keyword.get(build_backoff_opts, :jitter) == 0.5
    assert Keyword.get(build_backoff_opts, :jitter_strategy) == :factor

    assert_received {:build_policy_opts, build_policy_opts}
    assert Keyword.get(build_policy_opts, :max_attempts) == 4
    assert Keyword.get(build_policy_opts, :backoff) == :normalized_backoff
    assert is_function(Keyword.get(build_policy_opts, :retry_on), 1)
    assert is_function(Keyword.get(build_policy_opts, :retry_after_ms_fun), 1)

    assert_received {:with_retry_opts, with_retry_opts}
    assert Keyword.get(with_retry_opts, :max_attempts) == 4
    assert Keyword.get(with_retry_opts, :policy) == :http_retry_policy
  end

  test "rejects legacy retry aliases in retry policies" do
    context = %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: HttpPolicyRetryAdapter,
      telemetry: Pristine.Adapters.Telemetry.Noop,
      circuit_breaker: Pristine.Adapters.CircuitBreaker.Noop,
      rate_limiter: Pristine.Adapters.RateLimit.Noop,
      retry_policies: %{
        "default" => %{
          "max_retries" => 1
        }
      }
    }

    error =
      assert_raise ArgumentError, fn ->
        Pipeline.execute_endpoint(endpoint(retry: "default"), %{}, context)
      end

    assert String.contains?(error.message, "legacy retry option")
  end

  defp endpoint(overrides \\ []) do
    struct(
      EndpointMetadata,
      Keyword.merge(
        [
          id: "sample",
          method: "POST",
          path: "/sampling",
          headers: %{},
          query: %{}
        ],
        overrides
      )
    )
  end

  defp context do
    %Context{
      base_url: "https://example.com",
      transport: Pristine.TransportMock,
      serializer: Pristine.SerializerMock,
      retry: Pristine.RetryMock,
      telemetry: Pristine.TelemetryMock,
      circuit_breaker: Pristine.CircuitBreakerMock,
      rate_limiter: Pristine.RateLimitMock
    }
  end
end
