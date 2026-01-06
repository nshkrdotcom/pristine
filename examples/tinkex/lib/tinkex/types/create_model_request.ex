defmodule Tinkex.Types.CreateModelRequest do
  @moduledoc """
  Request type for creating a new model for training.

  This initializes a LoRA-based training model on top of a base model.
  The model is associated with a session and can be configured with
  custom LoRA parameters and user metadata.
  """

  alias Tinkex.Types.LoraConfig

  @enforce_keys [:session_id, :model_seq_id, :base_model]
  @derive {Jason.Encoder,
           only: [:session_id, :model_seq_id, :base_model, :user_metadata, :lora_config, :type]}
  defstruct [
    :session_id,
    :model_seq_id,
    :base_model,
    :user_metadata,
    lora_config: %LoraConfig{},
    type: "create_model"
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          model_seq_id: integer(),
          base_model: String.t(),
          user_metadata: map() | nil,
          lora_config: LoraConfig.t(),
          type: String.t()
        }
end
