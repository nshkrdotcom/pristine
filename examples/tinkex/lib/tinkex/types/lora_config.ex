defmodule Tinkex.Types.LoraConfig do
  @moduledoc """
  Configuration for LoRA (Low-Rank Adaptation) training.

  Mirrors Python tinker.types.LoraConfig.

  ## Fields

  - `rank` - Rank of LoRA matrices (default: 32)
  - `seed` - Random seed for reproducibility (default: nil)
  - `train_mlp` - Whether to train MLP layers (default: true)
  - `train_attn` - Whether to train attention layers (default: true)
  - `train_unembed` - Whether to train unembedding layers (default: true)
  """

  @derive {Jason.Encoder, only: [:rank, :seed, :train_mlp, :train_attn, :train_unembed]}
  defstruct rank: 32,
            seed: nil,
            train_mlp: true,
            train_attn: true,
            train_unembed: true

  @type t :: %__MODULE__{
          rank: pos_integer(),
          seed: integer() | nil,
          train_mlp: boolean(),
          train_attn: boolean(),
          train_unembed: boolean()
        }
end
