defmodule Tinkex.Types.SessionHeartbeatRequest do
  @moduledoc """
  Request type for sending a session heartbeat.

  Heartbeats keep sessions alive and prevent them from being garbage collected
  by the server. They should be sent periodically during long-running operations.
  """

  @enforce_keys [:session_id]
  defstruct [:session_id, type: "session_heartbeat"]

  @type t :: %__MODULE__{
          session_id: String.t(),
          type: String.t()
        }

  @doc """
  Creates a new SessionHeartbeatRequest for the given session ID.

  ## Examples

      iex> SessionHeartbeatRequest.new("sess_abc123")
      %SessionHeartbeatRequest{session_id: "sess_abc123", type: "session_heartbeat"}
  """
  @spec new(String.t()) :: t()
  def new(session_id) when is_binary(session_id) do
    %__MODULE__{session_id: session_id}
  end

  @doc """
  Converts the request to a JSON-encodable map.

  ## Examples

      iex> request = SessionHeartbeatRequest.new("sess_abc")
      iex> SessionHeartbeatRequest.to_json(request)
      %{"session_id" => "sess_abc", "type" => "session_heartbeat"}
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{session_id: session_id, type: type}) do
    %{"session_id" => session_id, "type" => type}
  end

  @doc """
  Parses a SessionHeartbeatRequest from a JSON-decoded map.

  Accepts both string-keyed and atom-keyed maps.

  ## Examples

      iex> SessionHeartbeatRequest.from_json(%{"session_id" => "sess_abc"})
      %SessionHeartbeatRequest{session_id: "sess_abc", type: "session_heartbeat"}

      iex> SessionHeartbeatRequest.from_json(%{session_id: "sess_abc"})
      %SessionHeartbeatRequest{session_id: "sess_abc", type: "session_heartbeat"}
  """
  @spec from_json(map()) :: t()
  def from_json(%{"session_id" => session_id}) do
    %__MODULE__{session_id: session_id}
  end

  def from_json(%{session_id: session_id}) do
    %__MODULE__{session_id: session_id}
  end
end
