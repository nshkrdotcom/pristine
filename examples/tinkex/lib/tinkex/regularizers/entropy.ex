defmodule Tinkex.Regularizers.Entropy do
  @moduledoc """
  Entropy regularizer.

  Encourages or discourages entropy in probability distributions.

  ## Formula

      H(p) = -Σ p_i × log(p_i)

  - Minimize entropy: Encourages confident predictions (low entropy)
  - Maximize entropy: Encourages diverse predictions (high entropy)

  ## Options

  - `:mode` - `:minimize` or `:maximize` (default: `:minimize`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:mean`)
  - `:temperature` - Temperature scaling (default: `1.0`)
  - `:normalize` - Whether to normalize by max entropy (default: `false`)

  ## Examples

      # Minimize entropy (encourage confident predictions)
      {penalty, metrics} = Entropy.compute(data, logprobs)

      # Maximize entropy (encourage exploration)
      {penalty, metrics} = Entropy.compute(data, logprobs, mode: :maximize)

      # With temperature scaling
      {penalty, metrics} = Entropy.compute(data, logprobs, temperature: 0.5)
  """

  @behaviour Tinkex.Regularizer

  @impl true
  def compute(_data, logprobs, opts \\ []) do
    mode = Keyword.get(opts, :mode, :minimize)
    reduction = Keyword.get(opts, :reduction, :mean)
    temperature = Keyword.get(opts, :temperature, 1.0)
    normalize = Keyword.get(opts, :normalize, false)

    tensor = to_tensor(logprobs)

    # Apply temperature scaling
    scaled_logprobs =
      if temperature != 1.0 do
        Nx.divide(tensor, temperature)
      else
        tensor
      end

    # Convert log probs to probs
    probs = Nx.exp(scaled_logprobs)

    # Compute entropy: H = -Σ p × log(p)
    # Using log probs directly: H = -Σ p × logprobs = -Σ exp(logprobs) × logprobs
    # Add small epsilon to avoid log(0)
    eps = 1.0e-10
    safe_probs = Nx.max(probs, eps)
    log_probs = Nx.log(safe_probs)
    pointwise = Nx.multiply(Nx.negate(probs), log_probs)

    # Reduce
    entropy =
      case reduction do
        :sum -> Nx.sum(pointwise)
        :mean -> Nx.mean(pointwise)
        _ -> Nx.mean(pointwise)
      end

    # Normalize by max entropy if requested
    entropy =
      if normalize do
        # Max entropy for uniform distribution: log(n)
        n = Nx.size(tensor)
        max_entropy = :math.log(n)
        Nx.divide(entropy, max_entropy)
      else
        entropy
      end

    # Mode determines sign:
    # - minimize: return entropy as penalty (low entropy = low penalty)
    # - maximize: return negative entropy (high entropy = low penalty)
    penalty =
      case mode do
        :minimize -> entropy
        :maximize -> Nx.negate(entropy)
        _ -> entropy
      end

    # Only compute metrics when not tracing
    metrics =
      if tracing?(tensor) do
        %{}
      else
        entropy_value = Nx.to_number(entropy)

        %{
          "entropy" => entropy_value,
          "entropy_penalty" => Nx.to_number(penalty),
          "mode" => to_string(mode),
          "mean_prob" => Nx.to_number(Nx.mean(probs)),
          "max_prob" => Nx.to_number(Nx.reduce_max(probs))
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "entropy"

  defp to_tensor(%Tinkex.Types.TensorData{} = td), do: Tinkex.Types.TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
  defp to_tensor(other), do: Nx.tensor(other)

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
