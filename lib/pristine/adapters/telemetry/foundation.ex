defmodule Pristine.Adapters.Telemetry.Foundation do
  @moduledoc """
  Telemetry adapter using the `:telemetry` library directly.

  This adapter provides full telemetry support including:
  - Event emission
  - Function timing with automatic duration measurement
  - Counter and gauge metrics

  Events are emitted under the `[:pristine, event_name]` prefix.

  ## Usage

      # Emit a custom event
      Foundation.emit(:request_completed, %{path: "/api"}, %{duration: 100})

      # Measure a function
      result = Foundation.measure(:database_query, %{table: "users"}, fn ->
        query_database()
      end)

      # Emit a counter
      Foundation.emit_counter(:request_count, %{method: :get})

      # Emit a gauge
      Foundation.emit_gauge(:queue_size, 42, %{queue: "jobs"})

  ## Event Naming

  All events are prefixed with `[:pristine]`. For example:
  - `emit(:request, ...)` emits `[:pristine, :request]`
  - `measure(:query, ...)` emits `[:pristine, :query]`
  """

  @behaviour Pristine.Ports.Telemetry

  @impl true
  @doc """
  Emit a telemetry event under the [:pristine, event] prefix.
  """
  def emit(event, metadata, measurements)
      when is_atom(event) and is_map(metadata) and is_map(measurements) do
    :telemetry.execute([:pristine, event], measurements, metadata)
    :ok
  end

  @impl true
  @doc """
  Measure function execution time and emit a telemetry event.

  Emits an event with `%{duration: duration_in_native_time}` measurement.
  If the function raises, the event is still emitted with `:error` metadata
  before re-raising.
  """
  def measure(event, metadata, fun)
      when is_atom(event) and is_map(metadata) and is_function(fun, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      emit(event, metadata, %{duration: duration})
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit(event, Map.put(metadata, :error, true), %{duration: duration})
        reraise e, __STACKTRACE__
    end
  end

  @impl true
  @doc """
  Emit a counter event (increment by 1).

  Emits an event with `%{count: 1}` measurement.
  """
  def emit_counter(event, metadata) when is_atom(event) and is_map(metadata) do
    emit(event, metadata, %{count: 1})
  end

  @impl true
  @doc """
  Emit a gauge event with a specific value.

  Emits an event with `%{value: value}` measurement.
  """
  def emit_gauge(event, value, metadata)
      when is_atom(event) and is_number(value) and is_map(metadata) do
    emit(event, metadata, %{value: value})
  end
end
