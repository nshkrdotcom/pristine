defmodule Tinkex.Regularizers.KLDivergence do
  @moduledoc """
  Kullback-Leibler divergence regularizer.

  Measures divergence between the model's distribution and a reference distribution.

  ## Formula

  Forward KL: D_KL(P || Q) = Σ p_i × log(p_i / q_i)
  Reverse KL: D_KL(Q || P) = Σ q_i × log(q_i / p_i)

  Where P is the model distribution (from logprobs) and Q is the reference.

  ## Options

  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:mean`)
  - `:direction` - `:forward` or `:reverse` (default: `:forward`)
  - `:symmetric` - Use symmetric KL: (D_KL(P||Q) + D_KL(Q||P)) / 2 (default: `false`)
  - `:reference_logprobs` - Direct reference tensor (log probabilities)
  - `:reference_field` - Field name to fetch reference from data
  - `:compute_reference` - Callback `fn(data, logprobs) -> reference_logprobs`

  ## Examples

      # With direct reference
      ref = Nx.tensor([-0.5, -0.5])  # log(0.5)
      {penalty, metrics} = KLDivergence.compute(data, logprobs,
        reference_logprobs: ref
      )

      # With symmetric KL
      {penalty, metrics} = KLDivergence.compute(data, logprobs,
        reference_logprobs: ref,
        symmetric: true
      )
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    reduction = Keyword.get(opts, :reduction, :mean)
    direction = Keyword.get(opts, :direction, :forward)
    symmetric = Keyword.get(opts, :symmetric, false)

    p_logprobs = to_tensor(logprobs)

    # During Nx.Defn tracing, return zero tensor
    if tracing?(p_logprobs) do
      zero = Nx.tensor(0.0, type: Nx.type(p_logprobs))
      {zero, %{}}
    else
      q_logprobs = resolve_reference!(data, opts)
      validate_shapes!(p_logprobs, q_logprobs)

      # Compute KL divergence
      kl = compute_kl(p_logprobs, q_logprobs, direction, symmetric, reduction)

      metrics = %{
        "kl_divergence" => Nx.to_number(kl),
        "direction" => to_string(direction),
        "symmetric" => symmetric
      }

      {kl, metrics}
    end
  end

  @impl true
  def name, do: "kl_divergence"

  # Compute KL divergence
  defp compute_kl(p_logprobs, q_logprobs, direction, symmetric, reduction) do
    if symmetric do
      # Symmetric KL: (D_KL(P||Q) + D_KL(Q||P)) / 2
      forward = compute_directional_kl(p_logprobs, q_logprobs, reduction)
      reverse = compute_directional_kl(q_logprobs, p_logprobs, reduction)
      Nx.divide(Nx.add(forward, reverse), 2.0)
    else
      case direction do
        :forward -> compute_directional_kl(p_logprobs, q_logprobs, reduction)
        :reverse -> compute_directional_kl(q_logprobs, p_logprobs, reduction)
        _ -> compute_directional_kl(p_logprobs, q_logprobs, reduction)
      end
    end
  end

  # D_KL(P || Q) = Σ p × log(p/q) = Σ p × (log_p - log_q)
  defp compute_directional_kl(p_logprobs, q_logprobs, reduction) do
    p = Nx.exp(p_logprobs)
    log_ratio = Nx.subtract(p_logprobs, q_logprobs)
    pointwise = Nx.multiply(p, log_ratio)

    case reduction do
      :sum -> Nx.sum(pointwise)
      :mean -> Nx.mean(pointwise)
      _ -> Nx.mean(pointwise)
    end
  end

  # Resolve reference distribution
  defp resolve_reference!(data, opts) do
    cond do
      ref = Keyword.get(opts, :reference_logprobs) ->
        to_tensor(ref)

      field = Keyword.get(opts, :reference_field) ->
        fetch_field!(data, field)

      compute_fn = Keyword.get(opts, :compute_reference) ->
        compute_fn.(data)

      true ->
        raise ArgumentError,
              "KL divergence requires :reference_logprobs, :reference_field, or :compute_reference option"
    end
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
