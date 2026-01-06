defmodule Tinkex.Types.Telemetry.TelemetryEvent do
  @moduledoc """
  Union type for all telemetry events.

  Mirrors Python tinker.types.telemetry_event.TelemetryEvent.

  This is a discriminated union type where the `event` field determines
  the concrete type:

  - `"SESSION_START"` -> SessionStartEvent
  - `"SESSION_END"` -> SessionEndEvent
  - `"UNHANDLED_EXCEPTION"` -> UnhandledExceptionEvent
  - `"GENERIC_EVENT"` -> GenericEvent
  """

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent
  }

  @type t ::
          GenericEvent.t()
          | SessionStartEvent.t()
          | SessionEndEvent.t()
          | UnhandledExceptionEvent.t()

  @doc """
  Parse a map into the appropriate event type based on the `event` discriminator.

  ## Examples

      {:ok, event} = TelemetryEvent.parse(%{"event" => "SESSION_START", ...})
      {:error, :unknown_event_type} = TelemetryEvent.parse(%{"event" => "INVALID"})
  """
  @spec parse(map()) :: {:ok, t()} | {:error, :unknown_event_type}
  def parse(%{"event" => "SESSION_START"} = data) do
    {:ok, SessionStartEvent.new(data)}
  end

  def parse(%{"event" => "SESSION_END"} = data) do
    {:ok, SessionEndEvent.new(data)}
  end

  def parse(%{"event" => "UNHANDLED_EXCEPTION"} = data) do
    {:ok, UnhandledExceptionEvent.new(data)}
  end

  def parse(%{"event" => "GENERIC_EVENT"} = data) do
    {:ok, GenericEvent.new(data)}
  end

  def parse(%{event: :session_start} = data) do
    {:ok, SessionStartEvent.new(data)}
  end

  def parse(%{event: :session_end} = data) do
    {:ok, SessionEndEvent.new(data)}
  end

  def parse(%{event: :unhandled_exception} = data) do
    {:ok, UnhandledExceptionEvent.new(data)}
  end

  def parse(%{event: :generic_event} = data) do
    {:ok, GenericEvent.new(data)}
  end

  def parse(_), do: {:error, :unknown_event_type}

  @doc """
  Get the event type of a telemetry event struct.

  ## Examples

      TelemetryEvent.type_of(%SessionStartEvent{...}) #=> :session_start
      TelemetryEvent.type_of(%GenericEvent{...}) #=> :generic_event
  """
  @spec type_of(t()) :: :session_start | :session_end | :unhandled_exception | :generic_event
  def type_of(%SessionStartEvent{}), do: :session_start
  def type_of(%SessionEndEvent{}), do: :session_end
  def type_of(%UnhandledExceptionEvent{}), do: :unhandled_exception
  def type_of(%GenericEvent{}), do: :generic_event
  def type_of(%{event: event}), do: event
end
