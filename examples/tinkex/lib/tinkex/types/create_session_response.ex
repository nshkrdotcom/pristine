defmodule Tinkex.Types.CreateSessionResponse do
  @moduledoc """
  Response type from creating a new Tinkex session.

  Contains the session ID and optional informational, warning, or error messages
  from the server.
  """

  @enforce_keys [:session_id]
  defstruct [:session_id, :info_message, :warning_message, :error_message]

  @type t :: %__MODULE__{
          session_id: String.t(),
          info_message: String.t() | nil,
          warning_message: String.t() | nil,
          error_message: String.t() | nil
        }

  @doc """
  Parses a CreateSessionResponse from a JSON-decoded map.

  ## Examples

      iex> CreateSessionResponse.from_json(%{"session_id" => "sess_abc123"})
      %CreateSessionResponse{session_id: "sess_abc123"}

      iex> CreateSessionResponse.from_json(%{"session_id" => "sess_xyz", "info_message" => "OK"})
      %CreateSessionResponse{session_id: "sess_xyz", info_message: "OK"}
  """
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      session_id: json["session_id"],
      info_message: json["info_message"],
      warning_message: json["warning_message"],
      error_message: json["error_message"]
    }
  end
end
