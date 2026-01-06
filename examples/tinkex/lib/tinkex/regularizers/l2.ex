defmodule Tinkex.Regularizers.L2 do
  @moduledoc """
  L2 weight decay regularizer.

  Computes the L2 norm (sum of squares) penalty for weight decay/ridge regression.

  ## Formula

      L2 = λ × Σx_i²

  Or with center:

      L2 = λ × Σ(x_i - c_i)²

  ## Options

  - `:target` - What to regularize: `:logprobs`, `:probs`, or `{:field, key}` (default: `:logprobs`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:sum`)
  - `:lambda` - Regularization strength (default: `1.0`)
  - `:center` - Optional center tensor for deviation-based L2 (default: `nil`)
  - `:clip` - Optional clipping value for the penalty (default: `nil`)

  ## Examples

      # Simple L2
      {penalty, metrics} = L2.compute(data, logprobs)

      # L2 with center (penalize deviation from reference)
      reference = Nx.tensor([0.5, 0.5])
      {penalty, metrics} = L2.compute(data, logprobs, center: reference)

      # L2 with clipping
      {penalty, metrics} = L2.compute(data, logprobs, clip: 10.0)
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    target = Keyword.get(opts, :target, :logprobs)
    reduction = Keyword.get(opts, :reduction, :sum)
    lambda = Keyword.get(opts, :lambda, 1.0)
    center = Keyword.get(opts, :center)
    clip = Keyword.get(opts, :clip)

    tensor = resolve_target!(data, logprobs, target)

    # Apply center if provided
    diff =
      if center do
        Nx.subtract(tensor, to_tensor(center))
      else
        tensor
      end

    # Compute L2 penalty: λ × reduction(x²)
    squared = Nx.pow(diff, 2)

    penalty =
      case reduction do
        :sum -> Nx.multiply(Nx.sum(squared), lambda)
        :mean -> Nx.multiply(Nx.mean(squared), lambda)
        _ -> Nx.multiply(Nx.sum(squared), lambda)
      end

    # Apply clipping if specified
    penalty =
      if clip do
        Nx.min(penalty, clip)
      else
        penalty
      end

    # Only compute metrics when not tracing
    metrics =
      if tracing?(tensor) do
        %{}
      else
        %{
          "l2_penalty" => Nx.to_number(penalty),
          "mean_squared" => Nx.to_number(Nx.mean(squared)),
          "rms" => Nx.to_number(Nx.sqrt(Nx.mean(squared))),
          "max_squared" => Nx.to_number(Nx.reduce_max(squared))
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "l2_weight_decay"

  # Target resolution (same as L1)

  defp resolve_target!(_data, logprobs, :logprobs), do: to_tensor(logprobs)

  defp resolve_target!(_data, logprobs, :probs) do
    logprobs
    |> to_tensor()
    |> Nx.exp()
  end

  defp resolve_target!(data, _logprobs, {:field, key}) do
    fetch_field!(data, key)
  end

  defp fetch_field!(data, key) do
    case data do
      [first | _] ->
        value = Map.get(first, key) || Map.get(first, to_string(key))

        if is_nil(value) do
          raise ArgumentError, "Field #{inspect(key)} not found in data"
        end

        to_tensor(value)

      [] ->
        raise ArgumentError, "Cannot fetch field from empty data list"
    end
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
  defp to_tensor(other), do: Nx.tensor(other)

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
