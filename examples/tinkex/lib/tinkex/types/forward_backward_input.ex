defmodule Tinkex.Types.ForwardBackwardInput do
  @moduledoc """
  Input type for forward-backward training passes.

  Contains training data (list of Datum structs), the loss function
  to use, and optional loss function configuration.
  """

  alias Tinkex.Types.Datum
  alias Tinkex.Types.LossFnType

  @enforce_keys [:data, :loss_fn]
  defstruct [:data, :loss_fn, :loss_fn_config]

  @type t :: %__MODULE__{
          data: [Datum.t()],
          loss_fn: LossFnType.t() | String.t(),
          loss_fn_config: map() | nil
        }

  defimpl Jason.Encoder do
    def encode(input, opts) do
      loss_fn_str =
        case input.loss_fn do
          atom when is_atom(atom) -> LossFnType.to_string(atom)
          str when is_binary(str) -> str
        end

      map = %{
        "data" => input.data,
        "loss_fn" => loss_fn_str,
        "loss_fn_config" => input.loss_fn_config
      }

      Jason.Encode.map(map, opts)
    end
  end
end
