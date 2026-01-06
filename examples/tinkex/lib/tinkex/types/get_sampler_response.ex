defmodule Tinkex.Types.GetSamplerResponse do
  @moduledoc """
  Response from the get_sampler API call.
  Mirrors Python `tinker.types.GetSamplerResponse`.
  """

  @enforce_keys [:sampler_id, :base_model]
  defstruct [:sampler_id, :base_model, :model_path]

  @type t :: %__MODULE__{
          sampler_id: String.t(),
          base_model: String.t(),
          model_path: String.t() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(%{"sampler_id" => sampler_id, "base_model" => base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json["model_path"]
    }
  end

  def from_json(%{sampler_id: sampler_id, base_model: base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json[:model_path]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.GetSamplerResponse do
  def encode(resp, opts) do
    map = %{
      sampler_id: resp.sampler_id,
      base_model: resp.base_model
    }

    map =
      if resp.model_path do
        Map.put(map, :model_path, resp.model_path)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
