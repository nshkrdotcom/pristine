defmodule Tinkex.Regularizers.Consistency do
  @moduledoc """
  Consistency regularizer.

  Enforces consistency between paired outputs by penalizing deviations
  between the current logprobs and a reference (e.g., original vs perturbed).

  ## Formula

      Consistency = metric(logprobs, reference)

  Where metric can be MSE (mean squared error), MAE, or cosine distance.

  ## Options

  - `:pair_field` - Field name in data to find reference (default: `"original_logprobs"`)
  - `:reference_logprobs` - Direct reference tensor (alternative to pair_field)
  - `:metric` - Comparison metric: `:mse`, `:mae`, `:cosine` (default: `:mse`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:mean`)

  ## Examples

      # With reference in data
      {penalty, metrics} = Consistency.compute(data, logprobs,
        pair_field: "original_logprobs"
      )

      # With direct reference
      {penalty, metrics} = Consistency.compute(data, logprobs,
        reference_logprobs: original,
        metric: :mse
      )
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    tensor = to_tensor(logprobs)

    # During Nx.Defn tracing, return zero tensor
    if tracing?(tensor) do
      zero = Nx.tensor(0.0, type: Nx.type(tensor))
      {zero, %{}}
    else
      pair_field = Keyword.get(opts, :pair_field, "original_logprobs")
      metric = Keyword.get(opts, :metric, :mse)
      reduction = Keyword.get(opts, :reduction, :mean)

      reference = resolve_reference!(data, opts, pair_field)
      validate_shapes!(tensor, reference)

      # Compute consistency penalty
      penalty = compute_metric(tensor, reference, metric, reduction)

      metrics = %{
        "consistency_penalty" => Nx.to_number(penalty),
        "metric" => to_string(metric),
        "mean_diff" => Nx.to_number(Nx.mean(Nx.abs(Nx.subtract(tensor, reference))))
      }

      {penalty, metrics}
    end
  end

  @impl true
  def name, do: "consistency"

  # Compute consistency metric
  defp compute_metric(a, b, :mse, reduction) do
    diff = Nx.subtract(a, b)
    squared = Nx.pow(diff, 2)

    case reduction do
      :sum -> Nx.sum(squared)
      :mean -> Nx.mean(squared)
      _ -> Nx.mean(squared)
    end
  end

  defp compute_metric(a, b, :mae, reduction) do
    abs_diff = Nx.abs(Nx.subtract(a, b))

    case reduction do
      :sum -> Nx.sum(abs_diff)
      :mean -> Nx.mean(abs_diff)
      _ -> Nx.mean(abs_diff)
    end
  end

  defp compute_metric(a, b, :cosine, _reduction) do
    # Cosine distance = 1 - cosine_similarity
    a_flat = Nx.flatten(a)
    b_flat = Nx.flatten(b)

    dot = Nx.sum(Nx.multiply(a_flat, b_flat))
    norm_a = Nx.sqrt(Nx.sum(Nx.pow(a_flat, 2)))
    norm_b = Nx.sqrt(Nx.sum(Nx.pow(b_flat, 2)))

    similarity = Nx.divide(dot, Nx.multiply(norm_a, norm_b))
    Nx.subtract(1.0, similarity)
  end

  defp compute_metric(a, b, _metric, reduction) do
    # Default to MSE
    compute_metric(a, b, :mse, reduction)
  end

  # Resolve reference distribution
  defp resolve_reference!(_data, opts, _pair_field) do
    case Keyword.get(opts, :reference_logprobs) do
      nil -> resolve_from_data!(opts)
      ref -> to_tensor(ref)
    end
  end

  defp resolve_from_data!(opts) do
    case Keyword.get(opts, :reference_logprobs) do
      nil ->
        raise ArgumentError,
              "Consistency requires :reference_logprobs option or data with pair_field"

      ref ->
        to_tensor(ref)
    end
  end

  defp validate_shapes!(a, b) do
    shape_a = Nx.shape(a)
    shape_b = Nx.shape(b)

    if shape_a != shape_b do
      raise ArgumentError,
            "Shape mismatch: logprobs has shape #{inspect(shape_a)}, " <>
              "reference has shape #{inspect(shape_b)}"
    end

    :ok
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
  defp to_tensor(other), do: Nx.tensor(other)

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
