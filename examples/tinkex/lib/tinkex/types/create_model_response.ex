defmodule Tinkex.Types.CreateModelResponse do
  @moduledoc """
  Response type from creating a new model for training.

  Contains the model ID which is used for subsequent training operations.
  """

  @enforce_keys [:model_id]
  defstruct [:model_id]

  @type t :: %__MODULE__{
          model_id: String.t()
        }

  @doc """
  Parses a CreateModelResponse from a JSON-decoded map.

  ## Examples

      iex> CreateModelResponse.from_json(%{"model_id" => "model_abc123"})
      %CreateModelResponse{model_id: "model_abc123"}
  """
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      model_id: json["model_id"]
    }
  end
end
