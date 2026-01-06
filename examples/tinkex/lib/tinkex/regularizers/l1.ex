defmodule Tinkex.Regularizers.L1 do
  @moduledoc """
  L1 sparsity regularizer.

  Computes the L1 norm (sum of absolute values) penalty to encourage sparsity.

  ## Formula

      L1 = λ × Σ|x_i|

  ## Options

  - `:target` - What to regularize: `:logprobs`, `:probs`, or `{:field, key}` (default: `:logprobs`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:sum`)
  - `:lambda` - Regularization strength (default: `1.0`)

  ## Examples

      # Simple usage
      {penalty, metrics} = L1.compute(data, logprobs)

      # With options
      {penalty, metrics} = L1.compute(data, logprobs,
        target: :probs,
        reduction: :mean,
        lambda: 0.01
      )

      # With custom field
      {penalty, metrics} = L1.compute(data, logprobs,
        target: {:field, :loss_fn_inputs}
      )
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    target = Keyword.get(opts, :target, :logprobs)
    reduction = Keyword.get(opts, :reduction, :sum)
    lambda = Keyword.get(opts, :lambda, 1.0)

    tensor = resolve_target!(data, logprobs, target)

    # Compute L1 penalty: λ × reduction(|x|)
    abs_tensor = Nx.abs(tensor)

    penalty =
      case reduction do
        :sum -> Nx.multiply(Nx.sum(abs_tensor), lambda)
        :mean -> Nx.multiply(Nx.mean(abs_tensor), lambda)
        _ -> Nx.multiply(Nx.sum(abs_tensor), lambda)
      end

    # Only compute metrics when not tracing
    metrics =
      if tracing?(tensor) do
        %{}
      else
        %{
          "l1_penalty" => Nx.to_number(penalty),
          "mean_abs" => Nx.to_number(Nx.mean(abs_tensor)),
          "max_abs" => Nx.to_number(Nx.reduce_max(abs_tensor)),
          "sparsity" => compute_sparsity(tensor)
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "l1_sparsity"

  # Target resolution

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

  # Detect Nx.Defn tracing
  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false

  # Compute sparsity ratio (fraction of near-zero values)
  defp compute_sparsity(tensor) do
    threshold = 1.0e-6
    total = Nx.size(tensor)
    near_zero = tensor |> Nx.abs() |> Nx.less(threshold) |> Nx.sum() |> Nx.to_number()
    near_zero / total
  end
end
