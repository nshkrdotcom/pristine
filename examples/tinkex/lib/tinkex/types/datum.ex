defmodule Tinkex.Types.Datum do
  @moduledoc """
  Training datum containing model input and optional loss function inputs.

  Mirrors Python tinker.types.Datum.

  ## Fields

  - `model_input` - Required. Model input containing chunks (text and/or images)
  - `loss_fn_inputs` - Map of named tensor data for loss function inputs

  ## Examples

      datum = Datum.new(%{
        model_input: ModelInput.from_ints([1, 2, 3]),
        loss_fn_inputs: %{
          "target_tokens" => TensorData.new([4, 5, 6], :int64, [3]),
          "weights" => TensorData.new([1.0, 1.0, 1.0], :float32, [3])
        }
      })
  """

  alias Tinkex.Types.{ModelInput, TensorData}

  @enforce_keys [:model_input]
  @derive {Jason.Encoder, only: [:model_input, :loss_fn_inputs]}
  defstruct [:model_input, loss_fn_inputs: %{}]

  @type t :: %__MODULE__{
          model_input: ModelInput.t(),
          loss_fn_inputs: %{String.t() => TensorData.t()}
        }

  @doc """
  Create a new Datum from a map.

  ## Parameters

  - `attrs` - Map with keys:
    - `:model_input` - Required. ModelInput struct
    - `:loss_fn_inputs` - Optional. Map of string keys to TensorData values

  ## Examples

      iex> model_input = ModelInput.from_ints([1, 2, 3])
      iex> Datum.new(%{model_input: model_input})
      %Datum{model_input: %ModelInput{...}, loss_fn_inputs: %{}}
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    model_input = Map.get(attrs, :model_input) || Map.fetch!(attrs, "model_input")
    loss_fn_inputs = Map.get(attrs, :loss_fn_inputs) || Map.get(attrs, "loss_fn_inputs", %{})

    %__MODULE__{
      model_input: model_input,
      loss_fn_inputs: normalize_loss_fn_inputs(loss_fn_inputs)
    }
  end

  defp normalize_loss_fn_inputs(inputs) when is_map(inputs) do
    inputs
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end
end
