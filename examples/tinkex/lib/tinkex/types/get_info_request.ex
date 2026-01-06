defmodule Tinkex.Types.GetInfoRequest do
  @moduledoc """
  Request type for getting model information.

  Used to retrieve metadata about a model including architecture,
  LoRA configuration, and tokenizer information.
  """

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :type]}
  defstruct [:model_id, type: "get_info"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t()
        }

  @doc """
  Creates a new GetInfoRequest for the given model ID.

  ## Examples

      iex> GetInfoRequest.new("model_abc123")
      %GetInfoRequest{model_id: "model_abc123", type: "get_info"}
  """
  @spec new(String.t()) :: t()
  def new(model_id) when is_binary(model_id) do
    %__MODULE__{model_id: model_id}
  end
end
