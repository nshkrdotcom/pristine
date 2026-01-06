defmodule Tinkex.Types.CustomLossOutput do
  @moduledoc """
  Output from custom loss computation with regularizers.

  Contains the total loss, base loss metrics, regularizer outputs,
  and gradient norm information.
  """

  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizer_total,
    :total_grad_norm,
    regularizers: %{}
  ]

  @type base_loss_metrics :: %{
          value: float(),
          grad_norm: float() | nil,
          custom: %{String.t() => number()}
        }

  @type t :: %__MODULE__{
          loss_total: float(),
          base_loss: base_loss_metrics() | nil,
          regularizers: %{String.t() => map()},
          regularizer_total: float() | nil,
          total_grad_norm: float() | nil
        }

  @doc """
  Build a CustomLossOutput from base loss and regularizer outputs.

  ## Parameters

  - `base_loss_value` - The base loss value
  - `base_loss_metrics` - Optional custom metrics map
  - `regularizer_outputs` - List of regularizer output maps with `:name` and `:contribution` keys
  - `opts` - Options:
    - `:base_grad_norm` - Gradient norm for base loss
    - `:total_grad_norm` - Total gradient norm

  ## Examples

      iex> CustomLossOutput.build(1.5, %{}, [%{name: "l2", contribution: 0.1}])
      %CustomLossOutput{loss_total: 1.6, ...}
  """
  @spec build(float(), map() | nil, list(map()), keyword()) :: t()
  def build(base_loss_value, base_loss_metrics, regularizer_outputs, opts \\ []) do
    base_grad_norm = Keyword.get(opts, :base_grad_norm)
    total_grad_norm = Keyword.get(opts, :total_grad_norm)

    regularizer_total =
      regularizer_outputs
      |> Enum.map(& &1.contribution)
      |> Enum.sum()

    regularizers_map =
      regularizer_outputs
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    %__MODULE__{
      loss_total: base_loss_value + regularizer_total,
      base_loss: %{
        value: base_loss_value,
        grad_norm: base_grad_norm,
        custom: base_loss_metrics || %{}
      },
      regularizers: regularizers_map,
      regularizer_total: regularizer_total,
      total_grad_norm: total_grad_norm
    }
  end

  @doc """
  Get the total loss value.
  """
  @spec loss(t()) :: float()
  def loss(%__MODULE__{loss_total: loss_total}), do: loss_total
end

defimpl Jason.Encoder, for: Tinkex.Types.CustomLossOutput do
  def encode(output, opts) do
    map = %{
      loss_total: output.loss_total,
      regularizer_total: output.regularizer_total,
      regularizers: output.regularizers
    }

    map =
      if output.base_loss do
        Map.put(map, :base_loss, output.base_loss)
      else
        map
      end

    map =
      if output.total_grad_norm do
        Map.put(map, :total_grad_norm, output.total_grad_norm)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
