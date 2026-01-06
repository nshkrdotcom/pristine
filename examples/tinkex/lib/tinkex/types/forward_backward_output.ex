defmodule Tinkex.Types.ForwardBackwardOutput do
  @moduledoc """
  Output type from forward-backward training passes.

  Contains the loss function output type, individual outputs per datum,
  and aggregated metrics including loss and gradient norms.
  """

  @enforce_keys [:loss_fn_output_type]
  defstruct [:loss_fn_output_type, loss_fn_outputs: [], metrics: %{}]

  @type t :: %__MODULE__{
          loss_fn_output_type: String.t(),
          loss_fn_outputs: [map()],
          metrics: %{String.t() => float()}
        }

  @doc """
  Parses a ForwardBackwardOutput from a JSON-decoded map.

  ## Examples

      iex> ForwardBackwardOutput.from_json(%{"loss_fn_output_type" => "cross_entropy", "metrics" => %{"loss" => 0.5}})
      %ForwardBackwardOutput{loss_fn_output_type: "cross_entropy", metrics: %{"loss" => 0.5}}
  """
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      loss_fn_output_type: json["loss_fn_output_type"],
      loss_fn_outputs: json["loss_fn_outputs"] || [],
      metrics: json["metrics"] || %{}
    }
  end

  @doc """
  Returns the loss value from metrics, or nil if not present.

  ## Examples

      iex> output = %ForwardBackwardOutput{loss_fn_output_type: "ce", metrics: %{"loss" => 0.42}}
      iex> ForwardBackwardOutput.loss(output)
      0.42
  """
  @spec loss(t()) :: float() | nil
  def loss(%__MODULE__{metrics: metrics}) do
    Map.get(metrics, "loss")
  end
end
