defmodule Tinkex.Types.CreateSamplingSessionRequest do
  @moduledoc """
  Request type for creating a new sampling session.

  A sampling session is used for text generation/inference operations.
  It can either use a base model directly or load fine-tuned weights
  from a checkpoint path.
  """

  @enforce_keys [:session_id, :sampling_session_seq_id]
  @derive {Jason.Encoder,
           only: [:session_id, :sampling_session_seq_id, :base_model, :model_path, :type]}
  defstruct [
    :session_id,
    :sampling_session_seq_id,
    :base_model,
    :model_path,
    type: "create_sampling_session"
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          sampling_session_seq_id: integer(),
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          type: String.t()
        }
end
