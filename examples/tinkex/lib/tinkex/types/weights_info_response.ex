defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc """
  Minimal information for loading public checkpoints.
  Mirrors Python `tinker.types.WeightsInfoResponse`.
  """

  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]

  @type t :: %__MODULE__{
          base_model: String.t(),
          is_lora: boolean(),
          lora_rank: non_neg_integer() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(%{"base_model" => base_model, "is_lora" => is_lora} = json) do
    %__MODULE__{
      base_model: base_model,
      is_lora: is_lora,
      lora_rank: json["lora_rank"]
    }
  end

  def from_json(%{base_model: base_model, is_lora: is_lora} = json) do
    %__MODULE__{
      base_model: base_model,
      is_lora: is_lora,
      lora_rank: json[:lora_rank]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.WeightsInfoResponse do
  def encode(resp, opts) do
    map = %{
      base_model: resp.base_model,
      is_lora: resp.is_lora
    }

    map =
      if resp.lora_rank do
        Map.put(map, :lora_rank, resp.lora_rank)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
