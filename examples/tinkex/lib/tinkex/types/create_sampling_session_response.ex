defmodule Tinkex.Types.CreateSamplingSessionResponse do
  @moduledoc """
  Response type from creating a new sampling session.

  Contains the sampling session ID which is used for subsequent
  sampling requests.
  """

  @enforce_keys [:sampling_session_id]
  defstruct [:sampling_session_id]

  @type t :: %__MODULE__{
          sampling_session_id: String.t()
        }

  @doc """
  Parses a CreateSamplingSessionResponse from a JSON-decoded map.

  ## Examples

      iex> CreateSamplingSessionResponse.from_json(%{"sampling_session_id" => "samp_abc123"})
      %CreateSamplingSessionResponse{sampling_session_id: "samp_abc123"}
  """
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      sampling_session_id: json["sampling_session_id"]
    }
  end
end
