defmodule Pristine.Ports.Telemetry do
  @moduledoc """
  Telemetry boundary for observability and metrics.

  This port provides a unified interface for emitting telemetry events,
  measuring function execution times, and recording counters/gauges.

  ## Required Callback

  - `emit/3` - Emit a telemetry event with measurements and metadata

  ## Optional Callbacks

  - `measure/3` - Time function execution and emit duration event
  - `emit_counter/2` - Emit a counter event
  - `emit_gauge/3` - Emit a gauge event with a specific value
  """

  @doc """
  Emit a telemetry event with measurements and metadata.

  ## Parameters

  - `event` - The event name (atom)
  - `metadata` - Additional context for the event
  - `measurements` - Numeric measurements for the event
  """
  @callback emit(event :: atom(), metadata :: map(), measurements :: map()) :: :ok

  @doc """
  Measure function execution time and emit a telemetry event.

  Wraps the function execution, measures its duration, and emits
  a telemetry event with the duration measurement.

  Returns the result of the function.
  """
  @callback measure(event :: atom(), metadata :: map(), (-> result)) :: result
            when result: term()

  @doc """
  Emit a counter event (increment by 1).

  Useful for tracking occurrences of events like requests, errors, etc.
  """
  @callback emit_counter(event :: atom(), metadata :: map()) :: :ok

  @doc """
  Emit a gauge event with a specific value.

  Useful for tracking point-in-time values like queue sizes,
  memory usage, active connections, etc.
  """
  @callback emit_gauge(event :: atom(), value :: number(), metadata :: map()) :: :ok

  @optional_callbacks [measure: 3, emit_counter: 2, emit_gauge: 3]
end
