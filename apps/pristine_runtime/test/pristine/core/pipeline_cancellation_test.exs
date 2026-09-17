defmodule Pristine.Core.PipelineCancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Adapters.{CircuitBreaker, RateLimit, Retry, Serializer}
  alias Pristine.Core.{Context, Request, Response}
  alias Pristine.{Cancellation, Error}

  defmodule LegacyTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :ordinary_send)
      {:ok, %Response{status: 200, headers: %{}, body: "{}"}}
    end
  end

  defmodule CancelableTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}) do
      %{unary_cancellation: :supported, cancellation_cleanup: :supported}
    end

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :ordinary_send)
      {:error, :ordinary_send_must_not_run}
    end

    @impl true
    def send_cancelable(
          %Request{},
          %Context{transport_opts: opts},
          %Cancellation{} = cancellation
        ) do
      Kernel.send(
        Keyword.fetch!(opts, :test_pid),
        {:cancelable_send, Cancellation.cancelled?(cancellation)}
      )

      {:ok, %Response{status: 200, headers: %{}, body: "{}"}}
    end
  end

  defmodule BlockingCancelableTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}) do
      %{unary_cancellation: :supported, cancellation_cleanup: :supported}
    end

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :ordinary_send)
      {:error, :ordinary_send_must_not_run}
    end

    @impl true
    def send_cancelable(
          %Request{},
          %Context{transport_opts: opts},
          %Cancellation{} = cancellation
        ) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :active_cancelable_send)

      case Cancellation.await(cancellation, :infinity) do
        :cancelled -> {:error, :cancelled}
      end
    end
  end

  defmodule RetryableCancelableTransport do
    @behaviour Pristine.Ports.Transport

    @impl true
    def capabilities(%Context{}) do
      %{unary_cancellation: :supported, cancellation_cleanup: :supported}
    end

    @impl true
    def send(%Request{}, %Context{transport_opts: opts}) do
      Kernel.send(Keyword.fetch!(opts, :test_pid), :ordinary_send)
      {:error, :ordinary_send_must_not_run}
    end

    @impl true
    def send_cancelable(
          %Request{headers: headers},
          %Context{transport_opts: opts},
          %Cancellation{}
        ) do
      Kernel.send(
        Keyword.fetch!(opts, :test_pid),
        {:cancelable_attempt, Map.get(headers, "x-stainless-retry-count")}
      )

      {:ok, %Response{status: 503, headers: %{}, body: "{}"}}
    end
  end

  defmodule ProbeRetry do
    @behaviour Pristine.Ports.Retry

    @impl true
    def with_retry(fun, opts) do
      send(Keyword.fetch!(opts, :test_pid), :retry_callback_ran)
      fun.()
    end
  end

  defmodule TestTelemetry do
    @behaviour Pristine.Ports.Telemetry

    @impl true
    def emit(event, metadata, measurements) do
      if pid = metadata[:test_pid] do
        send(pid, {:telemetry, event, metadata, measurements})
      end

      :ok
    end
  end

  @request %{id: "cancel-test", method: :get, path: "/v1/cancel-test"}

  test "pre-cancelled execution returns cancellation with zero transport sends" do
    cancellation = Cancellation.new()
    :ok = Cancellation.cancel(cancellation)
    context = context(LegacyTransport)

    assert {:error, %Error{type: :cancelled}} =
             Pristine.execute_request(@request, context, cancellation: cancellation)

    refute_received :ordinary_send
    assert_received {:telemetry, :request_start, _metadata, _measurements}

    assert_received {:telemetry, :request_stop,
                     %{result: :cancelled, retry_count: 0, classification: :cancelled},
                     %{duration: duration}}

    assert is_integer(duration)
  end

  test "pre-cancelled execution does not invoke the configured retry adapter" do
    cancellation = Cancellation.new()
    :ok = Cancellation.cancel(cancellation)

    context =
      context(LegacyTransport,
        retry: ProbeRetry,
        retry_opts: [test_pid: self()]
      )

    assert {:error, %Error{type: :cancelled}} =
             Pristine.execute_request(@request, context, cancellation: cancellation)

    refute_received :retry_callback_ran
    refute_received :ordinary_send
  end

  test "ordinary execution remains compatible with a legacy send/2-only transport" do
    context = context(LegacyTransport)

    assert {:ok, _response} = Pristine.execute_request(@request, context)
    assert_received :ordinary_send
  end

  test "invalid cancellation fails before egress" do
    context = context(LegacyTransport)

    assert {:error, {:invalid_cancellation, :expected_pristine_cancellation}} =
             Pristine.execute_request(@request, context, cancellation: make_ref())

    refute_received :ordinary_send
  end

  test "active cancellation fails closed on a legacy send/2-only transport" do
    cancellation = Cancellation.new()
    context = context(LegacyTransport)

    assert {:error, {:unsupported_transport_capabilities, LegacyTransport, missing}} =
             Pristine.execute_request(@request, context, cancellation: cancellation)

    assert missing.unary_cancellation == :unverified
    assert missing.cancellation_cleanup == :unverified
    refute_received :ordinary_send
  end

  test "active cancellation normalizes a cooperative transport cancellation" do
    cancellation = Cancellation.new()
    context = context(BlockingCancelableTransport)

    task =
      Task.async(fn ->
        Pristine.execute_request(@request, context, cancellation: cancellation)
      end)

    assert_receive :active_cancelable_send
    assert :ok = Cancellation.cancel(cancellation)
    assert {:error, %Error{type: :cancelled}} = Task.await(task)
    refute_received :ordinary_send

    assert_received {:telemetry, :request_stop,
                     %{result: :cancelled, retry_count: 0, classification: :cancelled},
                     %{duration: duration}}

    assert is_integer(duration)
  end

  test "cancellation during retry wait prevents the next attempt and retry header" do
    cancellation = Cancellation.new()
    parent = self()

    sleep_fun = fn _delay_ms ->
      send(parent, :retry_wait_started)
      Cancellation.await(cancellation, :infinity)
    end

    context =
      context(RetryableCancelableTransport,
        retry: Retry.Foundation,
        retry_opts: [
          max_attempts: 3,
          base_ms: 30_000,
          max_ms: 30_000,
          sleep_fun: sleep_fun
        ]
      )

    task =
      Task.async(fn ->
        Pristine.execute_request(@request, context, cancellation: cancellation)
      end)

    assert_receive {:cancelable_attempt, "0"}
    assert_receive :retry_wait_started
    assert :ok = Cancellation.cancel(cancellation)
    assert {:error, %Error{type: :cancelled}} = Task.await(task)
    refute_received {:cancelable_attempt, "1"}

    assert_received {:telemetry, :request_stop,
                     %{result: :cancelled, retry_count: 0, classification: :cancelled},
                     %{duration: duration}}

    assert is_integer(duration)
  end

  test "cancelable execution never silently falls back to send/2" do
    cancellation = Cancellation.new()
    context = context(CancelableTransport)

    assert {:ok, _response} =
             Pristine.execute_request(@request, context, cancellation: cancellation)

    assert_received {:cancelable_send, false}
    refute_received :ordinary_send
    assert :ok = Cancellation.cancel(cancellation)
    assert :ok = Cancellation.cancel(cancellation)
  end

  defp context(transport, overrides \\ []) do
    defaults = [
      base_url: "https://example.test",
      serializer: Serializer.JSON,
      transport: transport,
      transport_opts: [test_pid: self()],
      retry: Retry.Noop,
      rate_limiter: RateLimit.Noop,
      circuit_breaker: CircuitBreaker.Noop,
      telemetry: TestTelemetry,
      telemetry_metadata: %{test_pid: self()}
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Context.new()
  end
end
