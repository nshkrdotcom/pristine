defmodule Tinkex.Types.ForwardRequest do
  @moduledoc """
  Request type for forward-only inference API calls.

  Similar to ForwardBackwardRequest but uses `forward_input` field
  and calls the /api/v1/forward endpoint for inference without
  gradient computation.
  """

  alias Tinkex.Types.ForwardBackwardInput

  @enforce_keys [:forward_input, :model_id]
  @derive {Jason.Encoder, only: [:forward_input, :model_id, :seq_id]}
  defstruct [:forward_input, :model_id, :seq_id]

  @type t :: %__MODULE__{
          forward_input: ForwardBackwardInput.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
