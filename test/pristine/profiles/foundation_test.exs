defmodule Pristine.Profiles.FoundationTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Context
  alias Pristine.Profiles.Foundation, as: FoundationProfile
  alias TelemetryReporter.Event

  defmodule TestReporterTransport do
    @behaviour TelemetryReporter.Transport

    @impl true
    def send_batch(events, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:telemetry_batch, events})
      :ok
    end
  end

  describe "context/1" do
    test "builds a Foundation-backed production context with structured telemetry events" do
      context =
        FoundationProfile.context(
          base_url: "https://api.example.com",
          transport: Pristine.TransportMock,
          serializer: Pristine.SerializerMock,
          retry: [
            adapter: Pristine.RetryMock,
            policies: %{"default" => [max_attempts: 3]}
          ],
          rate_limit: [key: {:integration, :demo}, registry: :demo_registry],
          circuit_breaker: [registry: :demo_breakers],
          telemetry: [
            namespace: [:demo_sdk],
            metadata: %{service: :demo}
          ]
        )

      assert %Context{} = context
      assert context.retry == Pristine.RetryMock
      assert context.retry_policies == %{"default" => [max_attempts: 3]}
      assert context.rate_limiter == Pristine.Adapters.RateLimit.BackoffWindow
      assert context.rate_limit_opts[:key] == {:integration, :demo}
      assert context.rate_limit_opts[:registry] == :demo_registry
      assert context.circuit_breaker == Pristine.Adapters.CircuitBreaker.Foundation
      assert context.circuit_breaker_opts[:registry] == :demo_breakers
      assert context.telemetry == Pristine.Adapters.Telemetry.Foundation
      assert context.telemetry_events.request_start == [:demo_sdk, :request, :start]
      assert context.telemetry_events.request_stop == [:demo_sdk, :request, :stop]
      assert context.telemetry_events.request_exception == [:demo_sdk, :request, :exception]
      assert context.telemetry_metadata.service == :demo
      assert context.result_classifier == Pristine.Adapters.ResultClassifier.HTTP
    end

    test "supports explicitly disabling production seams" do
      context =
        FoundationProfile.context(
          base_url: "https://api.example.com",
          transport: Pristine.TransportMock,
          serializer: Pristine.SerializerMock,
          retry: false,
          rate_limit: false,
          circuit_breaker: false,
          telemetry: false,
          admission_control: false
        )

      assert context.retry == Pristine.Adapters.Retry.Noop
      assert context.rate_limiter == Pristine.Adapters.RateLimit.Noop
      assert context.circuit_breaker == Pristine.Adapters.CircuitBreaker.Noop
      assert context.telemetry == Pristine.Adapters.Telemetry.Noop
      assert context.admission_control == Pristine.Adapters.AdmissionControl.Noop
      assert context.telemetry_events == %{}
      assert context.telemetry_metadata == %{}
    end

    test "requires a dispatch server handle when admission control is enabled" do
      assert_raise ArgumentError, ~r/dispatch/, fn ->
        FoundationProfile.context(
          base_url: "https://api.example.com",
          transport: Pristine.TransportMock,
          serializer: Pristine.SerializerMock,
          admission_control: [enabled: true]
        )
      end
    end
  end

  describe "attach_reporter/2" do
    test "derives events from the context and forwards emitted telemetry into TelemetryReporter" do
      reporter_name = :"reporter_#{System.unique_integer([:positive])}"

      context =
        FoundationProfile.context(
          base_url: "https://api.example.com",
          transport: Pristine.TransportMock,
          serializer: Pristine.SerializerMock,
          rate_limit: false,
          circuit_breaker: false,
          telemetry: [namespace: [:demo_sdk]]
        )

      start_supervised!(
        {TelemetryReporter,
         name: reporter_name,
         transport: TestReporterTransport,
         transport_opts: [test_pid: self()],
         event_encoder: & &1,
         max_batch_size: 1,
         max_batch_delay: :timer.seconds(1)}
      )

      assert {:ok, handler_id} =
               FoundationProfile.attach_reporter(context,
                 reporter: reporter_name,
                 severity_mapper: fn _event, _measurements, metadata ->
                   if metadata[:result] == :error, do: :error, else: :info
                 end
               )

      on_exit(fn -> assert :ok = FoundationProfile.detach_reporter(handler_id) end)

      assert :ok =
               context.telemetry.emit(
                 context.telemetry_events.request_stop,
                 %{result: :ok, request_id: "req_123"},
                 %{duration: 42}
               )

      assert_receive {:telemetry_batch, [%Event{} = event]}
      assert event.name == "demo_sdk.request.stop"
      assert event.severity == :info
      assert event.data.measurements.duration == 42
      assert event.data.metadata.request_id == "req_123"
      assert event.data.metadata.result == :ok
    end
  end
end
