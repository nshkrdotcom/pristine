defmodule Tinkex.Types.OptimStepResponse do
  @moduledoc """
  Response type from optimizer step API calls.

  Contains metrics from the optimization step such as
  gradient norms and learning rate information.
  """

  defstruct [:metrics]

  @type t :: %__MODULE__{
          metrics: %{String.t() => float()} | nil
        }

  @doc """
  Parses an OptimStepResponse from a JSON-decoded map.

  ## Examples

      iex> OptimStepResponse.from_json(%{"metrics" => %{"grad_norm" => 1.5}})
      %OptimStepResponse{metrics: %{"grad_norm" => 1.5}}
  """
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      metrics: json["metrics"]
    }
  end

  @doc """
  Returns whether the optimization step was successful.

  Currently always returns true as a placeholder for future
  validation logic.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{}), do: true
end
