defmodule Tinkex.Types.SessionHeartbeatResponse do
  @moduledoc """
  Response type from a session heartbeat.

  A simple acknowledgment response indicating the heartbeat was received.
  """

  defstruct type: "session_heartbeat"

  @type t :: %__MODULE__{
          type: String.t()
        }

  @doc """
  Creates a new SessionHeartbeatResponse.

  ## Examples

      iex> SessionHeartbeatResponse.new()
      %SessionHeartbeatResponse{type: "session_heartbeat"}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Parses a SessionHeartbeatResponse from a JSON-decoded map.

  Accepts both string-keyed and atom-keyed maps, and handles
  unexpected input gracefully by returning a default response.

  ## Examples

      iex> SessionHeartbeatResponse.from_json(%{"type" => "session_heartbeat"})
      %SessionHeartbeatResponse{type: "session_heartbeat"}

      iex> SessionHeartbeatResponse.from_json(%{type: "session_heartbeat"})
      %SessionHeartbeatResponse{type: "session_heartbeat"}
  """
  @spec from_json(map()) :: t()
  def from_json(%{"type" => "session_heartbeat"}), do: new()
  def from_json(%{type: "session_heartbeat"}), do: new()
  def from_json(_), do: new()
end
