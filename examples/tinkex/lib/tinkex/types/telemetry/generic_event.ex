defmodule Tinkex.Types.Telemetry.GenericEvent do
  @moduledoc """
  Generic telemetry event with arbitrary event data.

  Mirrors Python tinker.types.generic_event.GenericEvent.

  ## Fields

  - `event` - Event type (always `:generic_event`)
  - `event_id` - Unique event identifier
  - `event_name` - Low-cardinality event name
  - `event_session_index` - Index within session
  - `severity` - Log severity level
  - `timestamp` - Event timestamp (DateTime)
  - `event_data` - Arbitrary structured JSON payload (default: `%{}`)
  """

  alias Tinkex.Types.Telemetry.{EventType, Severity}

  @enforce_keys [:event, :event_id, :event_name, :event_session_index, :severity, :timestamp]
  defstruct [
    :event,
    :event_id,
    :event_name,
    :event_session_index,
    :severity,
    :timestamp,
    event_data: %{}
  ]

  @type t :: %__MODULE__{
          event: EventType.t(),
          event_id: String.t(),
          event_name: String.t(),
          event_session_index: non_neg_integer(),
          severity: Severity.t(),
          timestamp: DateTime.t(),
          event_data: map()
        }

  @doc """
  Create a new GenericEvent from a map.

  Accepts both atom and string keys. String values for `event` and `severity`
  are automatically parsed to atoms. ISO8601 timestamp strings are parsed to DateTime.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      event: parse_event(get_attr(attrs, :event)),
      event_id: get_attr(attrs, :event_id),
      event_name: get_attr(attrs, :event_name),
      event_session_index: get_attr(attrs, :event_session_index),
      severity: parse_severity(get_attr(attrs, :severity)),
      timestamp: parse_timestamp(get_attr(attrs, :timestamp)),
      event_data: get_attr(attrs, :event_data) || %{}
    }
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp parse_event(event) when is_atom(event), do: event
  defp parse_event(event) when is_binary(event), do: EventType.parse(event)

  defp parse_severity(severity) when is_atom(severity), do: severity
  defp parse_severity(severity) when is_binary(severity), do: Severity.parse(severity)

  defp parse_timestamp(%DateTime{} = dt), do: dt

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_timestamp(_), do: nil

  defimpl Jason.Encoder do
    def encode(event, opts) do
      map = %{
        event: Tinkex.Types.Telemetry.EventType.to_string(event.event),
        event_id: event.event_id,
        event_name: event.event_name,
        event_session_index: event.event_session_index,
        severity: Tinkex.Types.Telemetry.Severity.to_string(event.severity),
        timestamp: DateTime.to_iso8601(event.timestamp),
        event_data: event.event_data
      }

      Jason.Encode.map(map, opts)
    end
  end
end
