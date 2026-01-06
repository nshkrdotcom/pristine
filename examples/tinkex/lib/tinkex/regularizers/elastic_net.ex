defmodule Tinkex.Regularizers.ElasticNet do
  @moduledoc """
  Elastic Net regularizer combining L1 and L2 penalties.

  ## Formula

      ElasticNet = λ × (α × L1 + (1 - α) × L2)
                 = λ × (α × Σ|x_i| + (1 - α) × Σx_i²)

  Where α (l1_ratio) controls the balance:
  - α = 1.0: Pure L1 (Lasso)
  - α = 0.0: Pure L2 (Ridge)
  - 0 < α < 1: Mixed (Elastic Net)

  ## Options

  - `:target` - What to regularize: `:logprobs`, `:probs`, or `{:field, key}` (default: `:logprobs`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:sum`)
  - `:lambda` - Overall regularization strength (default: `1.0`)
  - `:l1_ratio` - Balance between L1 and L2, 0.0-1.0 (default: `0.5`)

  ## Examples

      # Balanced elastic net
      {penalty, metrics} = ElasticNet.compute(data, logprobs)

      # More L1-like (sparsity)
      {penalty, metrics} = ElasticNet.compute(data, logprobs, l1_ratio: 0.8)

      # More L2-like (weight decay)
      {penalty, metrics} = ElasticNet.compute(data, logprobs, l1_ratio: 0.2)
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    target = Keyword.get(opts, :target, :logprobs)
    reduction = Keyword.get(opts, :reduction, :sum)
    lambda = Keyword.get(opts, :lambda, 1.0)
    l1_ratio = Keyword.get(opts, :l1_ratio, 0.5) |> clamp_ratio()

    tensor = resolve_target!(data, logprobs, target)

    # Compute L1 and L2 components
    abs_tensor = Nx.abs(tensor)
    squared = Nx.pow(tensor, 2)

    {l1_raw, l2_raw} =
      case reduction do
        :sum ->
          {Nx.sum(abs_tensor), Nx.sum(squared)}

        :mean ->
          {Nx.mean(abs_tensor), Nx.mean(squared)}

        _ ->
          {Nx.sum(abs_tensor), Nx.sum(squared)}
      end

    # Combine: λ × (α × L1 + (1 - α) × L2)
    l1_component = Nx.multiply(l1_raw, l1_ratio)
    l2_component = Nx.multiply(l2_raw, 1.0 - l1_ratio)
    penalty = Nx.multiply(Nx.add(l1_component, l2_component), lambda)

    # Only compute metrics when not tracing
    metrics =
      if tracing?(tensor) do
        %{}
      else
        %{
          "elastic_net_penalty" => Nx.to_number(penalty),
          "l1_component" => Nx.to_number(Nx.multiply(l1_raw, lambda * l1_ratio)),
          "l2_component" => Nx.to_number(Nx.multiply(l2_raw, lambda * (1.0 - l1_ratio))),
          "l1_ratio" => l1_ratio
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "elastic_net"

  # Clamp l1_ratio to valid range
  defp clamp_ratio(ratio) when ratio < 0.0, do: 0.0
  defp clamp_ratio(ratio) when ratio > 1.0, do: 1.0
  defp clamp_ratio(ratio), do: ratio

  # Target resolution (same as L1/L2)

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
