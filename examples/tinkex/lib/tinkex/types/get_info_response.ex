defmodule Tinkex.Types.GetInfoResponse do
  @moduledoc """
  Response type from getting model information.

  Contains model metadata including architecture, LoRA status,
  and tokenizer information.
  """

  @enforce_keys [:model_id, :model_data]
  defstruct [:model_id, :model_data, :is_lora, :lora_rank, :model_name, :type]

  @type t :: %__MODULE__{
          model_id: String.t(),
          model_data: map(),
          is_lora: boolean() | nil,
          lora_rank: non_neg_integer() | nil,
          model_name: String.t() | nil,
          type: String.t() | nil
        }

  @doc """
  Parses a GetInfoResponse from a JSON-decoded map.

  Accepts both string-keyed and atom-keyed maps.

  ## Examples

      iex> GetInfoResponse.from_json(%{"model_id" => "model_abc", "model_data" => %{}})
      %GetInfoResponse{model_id: "model_abc", model_data: %{}}
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    model_data = json["model_data"] || json[:model_data] || %{}

    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      model_data: model_data,
      is_lora: json["is_lora"] || json[:is_lora],
      lora_rank: json["lora_rank"] || json[:lora_rank],
      model_name: json["model_name"] || json[:model_name],
      type: json["type"] || json[:type]
    }
  end
end
