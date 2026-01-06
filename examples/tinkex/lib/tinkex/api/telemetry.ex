defmodule Tinkex.API.Telemetry do
  @moduledoc """
  HTTP API for sending telemetry events.

  Provides functions to send telemetry events to the Tinker telemetry endpoint.
  Events are sent as batches with session and platform metadata.

  ## Usage

      config = Tinkex.Config.new(api_key: "tml-key")

      # Build events
      event = Tinkex.Types.Telemetry.GenericEvent.new(%{
        event: :generic_event,
        event_id: UUID.uuid4(),
        event_name: "user_action",
        event_session_index: 1,
        severity: :info,
        timestamp: DateTime.utc_now(),
        event_data: %{"action" => "click"}
      })

      # Send events
      {:ok, response} = Tinkex.API.Telemetry.send_events(
        config,
        [event],
        "session-123",
        "elixir",
        "0.1.0"
      )

  ## Async Sending

  For fire-and-forget telemetry, use `send_async/3`:

      :ok = Tinkex.API.Telemetry.send_async(config, request)
  """

  alias Tinkex.API
  alias Tinkex.Config
  alias Tinkex.Error

  alias Tinkex.Types.Telemetry.TelemetrySendRequest
  alias Tinkex.Types.TelemetryResponse

  @endpoint "/api/v1/telemetry"

  @doc """
  Returns the telemetry API endpoint path.
  """
  @spec endpoint() :: String.t()
  def endpoint, do: @endpoint

  @doc """
  Send a telemetry request synchronously.

  Returns `{:ok, TelemetryResponse.t()}` on success or `{:error, Error.t()}` on failure.

  ## Options

  - `:http_client` - Custom HTTP client module (for testing)
  - `:timeout` - Request timeout in milliseconds
  """
  @spec send(Config.t(), TelemetrySendRequest.t(), keyword()) ::
          {:ok, TelemetryResponse.t()} | {:error, Error.t()}
  def send(config, %TelemetrySendRequest{} = request, opts \\ []) do
    client = http_client(config, opts)
    body = encode_request(request)

    case client.post(@endpoint, body, Keyword.merge(opts, config: config, pool_type: :training)) do
      {:ok, json} ->
        {:ok, TelemetryResponse.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Send telemetry events with session metadata.

  Convenience function that builds the request and sends it.

  ## Parameters

  - `config` - Tinkex configuration
  - `events` - List of telemetry event structs
  - `session_id` - Session identifier
  - `platform` - Platform name (e.g., "elixir")
  - `sdk_version` - SDK version string
  - `opts` - Additional options (same as `send/3`)
  """
  @spec send_events(Config.t(), [struct()], String.t(), String.t(), String.t(), keyword()) ::
          {:ok, TelemetryResponse.t()} | {:error, Error.t()}
  def send_events(config, events, session_id, platform, sdk_version, opts \\ []) do
    request = build_request(events, session_id, platform, sdk_version)
    send(config, request, opts)
  end

  @doc """
  Send a telemetry request synchronously (convenience wrapper).

  Takes the config from opts[:config] and calls `send/3`.

  ## Options

  - `:config` - Required. The Tinkex configuration
  - `:timeout` - Request timeout in milliseconds
  """
  @spec send_sync(TelemetrySendRequest.t(), keyword()) ::
          {:ok, TelemetryResponse.t()} | {:error, Error.t()}
  def send_sync(%TelemetrySendRequest{} = request, opts) do
    config = Keyword.fetch!(opts, :config)
    send(config, request, opts)
  end

  @doc """
  Send a telemetry request asynchronously (fire-and-forget).

  Returns `:ok` immediately. Errors are logged but not propagated.

  ## Options

  Same as `send/3`.
  """
  @spec send_async(Config.t(), TelemetrySendRequest.t(), keyword()) :: :ok
  def send_async(config, %TelemetrySendRequest{} = request, opts \\ []) do
    Task.start(fn ->
      case send(config, request, opts) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          # Log error but don't propagate
          require Logger
          Logger.warning("Telemetry send failed: #{inspect(error)}")
      end
    end)

    :ok
  end

  @doc """
  Build a TelemetrySendRequest from events and metadata.

  ## Parameters

  - `events` - List of telemetry event structs
  - `session_id` - Session identifier
  - `platform` - Platform name
  - `sdk_version` - SDK version string
  """
  @spec build_request([struct()], String.t(), String.t(), String.t()) :: TelemetrySendRequest.t()
  def build_request(events, session_id, platform, sdk_version) do
    TelemetrySendRequest.new(%{
      events: events,
      session_id: session_id,
      platform: platform,
      sdk_version: sdk_version
    })
  end

  # Private functions

  defp http_client(config, opts) do
    case Keyword.get(opts, :http_client) do
      nil -> API.client_module(config: config)
      client -> client
    end
  end

  defp encode_request(%TelemetrySendRequest{} = request) do
    # Encode the request to a JSON-compatible map
    # Events need to be encoded through their Jason.Encoder implementations
    %{
      "events" => Enum.map(request.events, &encode_event/1),
      "platform" => request.platform,
      "sdk_version" => request.sdk_version,
      "session_id" => request.session_id
    }
  end

  defp encode_event(event) do
    # Use Jason to encode and decode to get the wire format
    event
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
