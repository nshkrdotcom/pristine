defmodule Tinkex.Types.Telemetry.TelemetryBatch do
  @moduledoc """
  Batch of telemetry events.

  Mirrors Python tinker.types.telemetry_batch.TelemetryBatch.

  This is a response type that allows extra fields (forward compatibility).

  ## Fields

  - `events` - List of TelemetryEvent structs
  - `platform` - Host platform name (e.g., "elixir", "python")
  - `sdk_version` - SDK version string
  - `session_id` - Session identifier
  """

  alias Tinkex.Types.Telemetry.TelemetryEvent

  @enforce_keys [:events, :platform, :sdk_version, :session_id]
  defstruct [:events, :platform, :sdk_version, :session_id]

  @type t :: %__MODULE__{
          events: [TelemetryEvent.t()],
          platform: String.t(),
          sdk_version: String.t(),
          session_id: String.t()
        }

  @doc """
  Create a new TelemetryBatch from a map.

  Accepts both atom and string keys.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      events: get_attr(attrs, :events) || [],
      platform: get_attr(attrs, :platform),
      sdk_version: get_attr(attrs, :sdk_version),
      session_id: get_attr(attrs, :session_id)
    }
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defimpl Jason.Encoder do
    def encode(batch, opts) do
      map = %{
        events: batch.events,
        platform: batch.platform,
        sdk_version: batch.sdk_version,
        session_id: batch.session_id
      }

      Jason.Encode.map(map, opts)
    end
  end
end
