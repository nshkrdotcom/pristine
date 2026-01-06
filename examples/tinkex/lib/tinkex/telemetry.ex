defmodule Tinkex.Telemetry do
  @moduledoc """
  Convenience helpers for wiring Tinkex telemetry into console logging or
  lightweight dashboards.

  ## Usage

  ### Simple Console Logging

      # Attach logger to print telemetry events
      handler_id = Tinkex.Telemetry.attach_logger()

      # Later, detach when done
      :ok = Tinkex.Telemetry.detach(handler_id)

  ### Initialize Reporter for Session

      {:ok, reporter} = Tinkex.Telemetry.init(
        session_id: "session-123",
        config: config,
        telemetry_opts: [flush_interval_ms: 5_000]
      )
  """

  require Logger

  alias Tinkex.Telemetry.Reporter

  @default_events [
    [:tinkex, :http, :request, :start],
    [:tinkex, :http, :request, :stop],
    [:tinkex, :http, :request, :exception],
    [:tinkex, :queue, :state_change]
  ]

  @doc """
  Attach a logger that prints HTTP and queue-state telemetry events to the console.

  Returns the handler id so callers can detach it manually.

  ## Options

    * `:handler_id` - Custom handler ID (default: auto-generated)
    * `:events` - List of telemetry events to handle (default: HTTP + queue events)
    * `:level` - Log level to use (default: `:info`)

  ## Examples

      handler_id = Tinkex.Telemetry.attach_logger()
      # ...do work...
      :ok = Tinkex.Telemetry.detach(handler_id)

      # With custom options
      handler_id = Tinkex.Telemetry.attach_logger(
        handler_id: "my-handler",
        level: :debug
      )
  """
  @spec attach_logger(keyword()) :: term()
  def attach_logger(opts \\ []) do
    handler_id = opts[:handler_id] || "tinkex-telemetry-#{:erlang.unique_integer([:positive])}"
    events = opts[:events] || @default_events
    level = opts[:level] || :info

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, %{level: level})
    handler_id
  end

  @doc """
  Detach a previously attached handler.

  Returns `:ok` if successful, `{:error, :not_found}` if handler doesn't exist.
  """
  @spec detach(term()) :: :ok | {:error, :not_found}
  def detach(handler_id), do: :telemetry.detach(handler_id)

  @doc """
  Initialize a telemetry reporter for a session.

  ## Options

    * `:session_id` (**required**) - The session ID
    * `:config` (**required**) - `Tinkex.Config.t()`
    * `:enabled?` - Override env flag (default: check config's `telemetry_enabled?`)
    * `:telemetry_opts` - Options passed to `Reporter.start_link/1`

  ## Returns

    * `{:ok, pid}` on success
    * `:ignore` when disabled
    * `{:error, reason}` on failure

  Treats `{:error, {:already_started, pid}}` as success.

  ## Examples

      {:ok, reporter} = Tinkex.Telemetry.init(
        session_id: "session-123",
        config: config,
        telemetry_opts: [flush_interval_ms: 5_000]
      )
  """
  @spec init(keyword()) :: {:ok, pid()} | :ignore | {:error, term()}
  def init(opts) do
    with {:ok, session_id} <- fetch_required(opts, :session_id),
         {:ok, config} <- fetch_required(opts, :config) do
      enabled? =
        Keyword.get_lazy(opts, :enabled?, fn ->
          case config do
            %{telemetry_enabled?: false} -> false
            _ -> true
          end
        end)

      if enabled? do
        telemetry_opts = Keyword.get(opts, :telemetry_opts, [])

        reporter_opts =
          telemetry_opts
          |> Keyword.put(:session_id, session_id)
          |> Keyword.put(:config, config)
          |> Keyword.put(:enabled, true)

        case Reporter.start_link(reporter_opts) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
      else
        :ignore
      end
    end
  end

  # Telemetry event handlers

  @doc false
  def handle_event([:tinkex, :http, :request, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "HTTP #{metadata.method} #{metadata.path} start (pool=#{metadata.pool_type} base=#{metadata.base_url})"
    end)
  end

  def handle_event([:tinkex, :http, :request, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.log(config.level, fn ->
      "HTTP #{metadata.method} #{metadata.path} #{metadata.result} in #{duration_ms}ms " <>
        "retries=#{metadata[:retry_count] || 0} base=#{metadata.base_url}"
    end)
  end

  def handle_event([:tinkex, :http, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "HTTP #{metadata.method} #{metadata.path} exception after #{duration_ms}ms reason=#{inspect(metadata.reason)}"
    )
  end

  def handle_event([:tinkex, :queue, :state_change], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Queue state changed to #{metadata.queue_state} (request_id=#{metadata.request_id})"
    end)
  end

  def handle_event(event, _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Unhandled telemetry #{inspect(event)} #{inspect(metadata)}"
    end)
  end

  # Private helpers

  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end
end
