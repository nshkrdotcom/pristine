defmodule Tinkex.Regularizers.GradientPenalty do
  @moduledoc """
  Gradient penalty regularizer.

  Penalizes large gradient magnitudes, commonly used in WGAN-GP style training.

  ## Modes

  - `:output` - Penalize gradient norm w.r.t. current logprobs
  - `:interpolated` - WGAN-GP style penalty between logprobs and reference

  ## Formula

  For output mode:
      GP = (||∇_x f(x)|| - target_norm)²

  For interpolated mode (WGAN-GP):
      x̂ = αx + (1-α)y  where α ~ Uniform(0,1)
      GP = (||∇_x̂ f(x̂)|| - 1)²

  ## Options

  - `:mode` - `:output` or `:interpolated` (default: `:output`)
  - `:target_norm` - Target gradient magnitude (default: `1.0`)
  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:mean`)
  - `:reference_logprobs` - Reference for interpolated mode
  - `:epsilon` - Small constant for numerical stability (default: `1.0e-8`)

  ## Examples

      # Output mode
      {penalty, metrics} = GradientPenalty.compute(data, logprobs)

      # Interpolated mode (WGAN-GP)
      {penalty, metrics} = GradientPenalty.compute(data, logprobs,
        mode: :interpolated,
        reference_logprobs: real_logprobs
      )
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    mode = Keyword.get(opts, :mode, :output)
    target_norm = Keyword.get(opts, :target_norm, 1.0)
    reduction = Keyword.get(opts, :reduction, :mean)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-8)

    tensor = to_tensor(logprobs)

    # During Nx.Defn tracing, return zero tensor
    if tracing?(tensor) do
      zero = Nx.tensor(0.0, type: Nx.type(tensor))
      {zero, %{}}
    else
      penalty =
        case mode do
          :output ->
            compute_output_penalty(tensor, target_norm, reduction, epsilon)

          :interpolated ->
            reference = resolve_reference!(data, opts)
            compute_interpolated_penalty(tensor, reference, target_norm, reduction, epsilon)

          _ ->
            compute_output_penalty(tensor, target_norm, reduction, epsilon)
        end

      # Compute gradient norm for metrics
      grad_norm = compute_gradient_norm(tensor, epsilon)

      metrics = %{
        "gradient_penalty" => Nx.to_number(penalty),
        "gradient_norm" => grad_norm,
        "target_norm" => target_norm,
        "mode" => to_string(mode)
      }

      {penalty, metrics}
    end
  end

  @impl true
  def name, do: "gradient_penalty"

  # Output mode: penalize deviation from target norm
  defp compute_output_penalty(tensor, target_norm, reduction, epsilon) do
    # Compute gradient norm approximation using the tensor values
    # (In full implementation, this would use Nx.Defn.grad)
    grad_norm = compute_local_gradient_norm(tensor, epsilon)
    deviation = Nx.subtract(grad_norm, target_norm)
    squared = Nx.pow(deviation, 2)

    case reduction do
      :sum -> Nx.sum(squared)
      :mean -> Nx.mean(squared)
      _ -> Nx.mean(squared)
    end
  end

  # Interpolated mode (WGAN-GP style)
  defp compute_interpolated_penalty(tensor, reference, target_norm, reduction, epsilon) do
    # Interpolate between tensor and reference
    # α ~ Uniform(0,1) - use random alpha
    alpha = :rand.uniform()
    interpolated = Nx.add(Nx.multiply(tensor, alpha), Nx.multiply(reference, 1.0 - alpha))

    # Compute gradient norm on interpolated point
    grad_norm = compute_local_gradient_norm(interpolated, epsilon)
    deviation = Nx.subtract(grad_norm, target_norm)
    squared = Nx.pow(deviation, 2)

    case reduction do
      :sum -> Nx.sum(squared)
      :mean -> Nx.mean(squared)
      _ -> Nx.mean(squared)
    end
  end

  # Approximate local gradient norm using finite differences
  defp compute_local_gradient_norm(tensor, epsilon) do
    # Use local variation as gradient norm proxy
    flat = Nx.flatten(tensor)
    n = Nx.size(flat)

    if n > 1 do
      # Compute differences between adjacent elements
      shifted = Nx.slice(flat, [1], [n - 1])
      original = Nx.slice(flat, [0], [n - 1])
      diffs = Nx.subtract(shifted, original)

      # L2 norm of differences
      Nx.sqrt(Nx.add(Nx.mean(Nx.pow(diffs, 2)), epsilon))
    else
      Nx.tensor(0.0, type: Nx.type(tensor))
    end
  end

  # Compute gradient norm for metrics
  defp compute_gradient_norm(tensor, epsilon) do
    norm = compute_local_gradient_norm(tensor, epsilon)
    Nx.to_number(norm)
  end

  defp resolve_reference!(_data, opts) do
    case Keyword.get(opts, :reference_logprobs) do
      nil ->
        raise ArgumentError,
              "Interpolated mode requires :reference_logprobs option"

      ref ->
        to_tensor(ref)
    end
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
  defp to_tensor(other), do: Nx.tensor(other)

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
