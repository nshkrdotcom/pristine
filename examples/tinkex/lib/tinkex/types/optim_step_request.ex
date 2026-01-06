defmodule Tinkex.Types.OptimStepRequest do
  @moduledoc """
  Request type for optimizer step API calls.

  Contains Adam optimizer parameters and model identification
  for applying gradient updates to model weights.
  """

  alias Tinkex.Types.AdamParams

  @enforce_keys [:adam_params, :model_id]
  @derive {Jason.Encoder, only: [:adam_params, :model_id, :seq_id]}
  defstruct [:adam_params, :model_id, :seq_id]

  @type t :: %__MODULE__{
          adam_params: AdamParams.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
