defmodule Tinkex.API.TelemetryTest do
  @moduledoc """
  Tests for the Telemetry API module.
  """
  use ExUnit.Case, async: true

  alias Tinkex.API.Telemetry, as: TelemetryAPI
  alias Tinkex.Config

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent,
    TelemetrySendRequest
  }

  alias Tinkex.Types.TelemetryResponse

  # Mock HTTP client for testing
  defmodule MockHTTPClient do
    @moduledoc false

    def post("/api/v1/telemetry", body, opts) do
      send(self(), {:telemetry_post, body, opts})
      {:ok, %{"status" => "accepted"}}
    end

    def post("/api/v1/telemetry/fail", _body, _opts) do
      {:error, %{status: 500, message: "Internal server error"}}
    end
  end

  setup do
    config = Config.new(api_key: "tml-test-api-key", base_url: "https://api.test.com")
    {:ok, config: config}
  end

  describe "send/3" do
    test "sends telemetry events successfully", %{config: config} do
      now = DateTime.utc_now()

      events = [
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })
      ]

      request =
        TelemetrySendRequest.new(%{
          events: events,
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-123"
        })

      result = TelemetryAPI.send(config, request, http_client: MockHTTPClient)

      assert {:ok, %TelemetryResponse{status: "accepted"}} = result
      assert_received {:telemetry_post, body, opts}
      assert body["session_id"] == "sess-123"
      assert body["platform"] == "elixir"
      assert length(body["events"]) == 1
      assert Keyword.get(opts, :config) == config
    end

    test "sends multiple event types in a batch", %{config: config} do
      now = DateTime.utc_now()

      events = [
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        }),
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-2",
          event_name: "test_event",
          event_session_index: 1,
          severity: :info,
          timestamp: now,
          event_data: %{"key" => "value"}
        }),
        SessionEndEvent.new(%{
          event: :session_end,
          event_id: "evt-3",
          event_session_index: 2,
          severity: :info,
          timestamp: now,
          duration: "PT1H"
        })
      ]

      request =
        TelemetrySendRequest.new(%{
          events: events,
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-456"
        })

      result = TelemetryAPI.send(config, request, http_client: MockHTTPClient)

      assert {:ok, %TelemetryResponse{}} = result
      assert_received {:telemetry_post, body, _opts}
      assert length(body["events"]) == 3
    end

    test "sends exception events", %{config: config} do
      now = DateTime.utc_now()

      events = [
        UnhandledExceptionEvent.new(%{
          event: :unhandled_exception,
          event_id: "evt-exc",
          event_session_index: 5,
          severity: :error,
          timestamp: now,
          error_message: "Something went wrong",
          error_type: "RuntimeError",
          traceback: "line 1\nline 2"
        })
      ]

      request =
        TelemetrySendRequest.new(%{
          events: events,
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-789"
        })

      result = TelemetryAPI.send(config, request, http_client: MockHTTPClient)

      assert {:ok, %TelemetryResponse{}} = result
      assert_received {:telemetry_post, body, _opts}
      [event] = body["events"]
      assert event["event"] == "UNHANDLED_EXCEPTION"
      assert event["error_message"] == "Something went wrong"
    end
  end

  describe "send_events/5" do
    test "creates request and sends events", %{config: config} do
      now = DateTime.utc_now()

      events = [
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })
      ]

      result =
        TelemetryAPI.send_events(
          config,
          events,
          "sess-auto",
          "elixir",
          "0.1.0",
          http_client: MockHTTPClient
        )

      assert {:ok, %TelemetryResponse{}} = result
      assert_received {:telemetry_post, body, _opts}
      assert body["session_id"] == "sess-auto"
    end
  end

  describe "send_async/3" do
    test "sends telemetry asynchronously", %{config: config} do
      now = DateTime.utc_now()

      events = [
        GenericEvent.new(%{
          event: :generic_event,
          event_id: "evt-async",
          event_name: "async_test",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })
      ]

      request =
        TelemetrySendRequest.new(%{
          events: events,
          platform: "elixir",
          sdk_version: "0.1.0",
          session_id: "sess-async"
        })

      # Async send returns :ok immediately
      result = TelemetryAPI.send_async(config, request, http_client: MockHTTPClient)
      assert result == :ok
    end
  end

  describe "build_request/4" do
    test "builds a TelemetrySendRequest" do
      now = DateTime.utc_now()

      events = [
        SessionStartEvent.new(%{
          event: :session_start,
          event_id: "evt-1",
          event_session_index: 0,
          severity: :info,
          timestamp: now
        })
      ]

      request = TelemetryAPI.build_request(events, "sess-build", "elixir", "0.2.0")

      assert %TelemetrySendRequest{} = request
      assert request.session_id == "sess-build"
      assert request.platform == "elixir"
      assert request.sdk_version == "0.2.0"
      assert length(request.events) == 1
    end
  end

  describe "endpoint/0" do
    test "returns the telemetry endpoint path" do
      assert TelemetryAPI.endpoint() == "/api/v1/telemetry"
    end
  end
end
