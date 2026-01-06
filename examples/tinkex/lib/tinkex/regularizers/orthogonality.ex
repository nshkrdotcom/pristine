defmodule Tinkex.Regularizers.Orthogonality do
  @moduledoc """
  Orthogonality regularizer.

  Encourages orthogonal weight matrices for better gradient flow
  and decorrelation of learned features.

  ## Formula

  For a matrix W:
      Ortho = ||W^T W - I||²_F

  Where ||·||_F is the Frobenius norm.

  For 1D tensors, this measures deviation from unit norm:
      Ortho = (||x||² - 1)²

  ## Options

  - `:reduction` - How to reduce: `:sum`, `:mean` (default: `:mean`)
  - `:epsilon` - Small constant for numerical stability (default: `1.0e-8`)

  ## Examples

      # Orthogonality on weight matrix
      weights = Nx.tensor([[1.0, 0.0], [0.0, 1.0]])
      {penalty, metrics} = Orthogonality.compute([], weights)
      # For identity matrix, penalty should be ~0

      # Orthogonality on 1D tensor (unit norm)
      {penalty, metrics} = Orthogonality.compute([], logprobs)
  """

  @behaviour Tinkex.Regularizer

  alias Tinkex.Types.TensorData

  @impl true
  def compute(_data, logprobs, opts \\ []) do
    reduction = Keyword.get(opts, :reduction, :mean)
    epsilon = Keyword.get(opts, :epsilon, 1.0e-8)

    tensor = to_tensor(logprobs)

    # During Nx.Defn tracing, return zero tensor
    if tracing?(tensor) do
      zero = Nx.tensor(0.0, type: Nx.type(tensor))
      {zero, %{}}
    else
      penalty = compute_orthogonality_penalty(tensor, reduction, epsilon)

      metrics = %{
        "orthogonality_penalty" => Nx.to_number(penalty),
        "tensor_norm" => compute_frobenius_norm(tensor)
      }

      {penalty, metrics}
    end
  end

  @impl true
  def name, do: "orthogonality"

  # Compute orthogonality penalty based on tensor shape
  defp compute_orthogonality_penalty(tensor, reduction, epsilon) do
    shape = Nx.shape(tensor)

    case tuple_size(shape) do
      1 ->
        # 1D: penalize deviation from unit norm
        compute_unit_norm_penalty(tensor, epsilon)

      2 ->
        # 2D: penalize deviation from orthogonality
        compute_matrix_orthogonality_penalty(tensor, reduction, epsilon)

      _ ->
        # Higher dimensions: reshape to 2D and compute
        flat_shape = {elem(shape, 0), div(Nx.size(tensor), elem(shape, 0))}
        reshaped = Nx.reshape(tensor, flat_shape)
        compute_matrix_orthogonality_penalty(reshaped, reduction, epsilon)
    end
  end

  # For 1D tensor: (||x||² - 1)²
  defp compute_unit_norm_penalty(tensor, _epsilon) do
    norm_squared = Nx.sum(Nx.pow(tensor, 2))
    deviation = Nx.subtract(norm_squared, 1.0)
    Nx.pow(deviation, 2)
  end

  # For 2D matrix: ||W^T W - I||²_F
  defp compute_matrix_orthogonality_penalty(tensor, reduction, _epsilon) do
    {rows, cols} = Nx.shape(tensor)

    # For tall matrices (rows >= cols): W^T W should be identity
    # For wide matrices (rows < cols): W W^T should be identity
    {gram, size} =
      if rows >= cols do
        {Nx.dot(Nx.transpose(tensor), tensor), cols}
      else
        {Nx.dot(tensor, Nx.transpose(tensor)), rows}
      end

    # Create identity matrix
    identity = Nx.eye(size, type: Nx.type(tensor))

    # Compute ||Gram - I||²_F
    diff = Nx.subtract(gram, identity)
    frobenius_sq = Nx.sum(Nx.pow(diff, 2))

    case reduction do
      :sum -> frobenius_sq
      :mean -> Nx.divide(frobenius_sq, size * size)
      _ -> Nx.divide(frobenius_sq, size * size)
    end
  end

  # Compute Frobenius norm for metrics
  defp compute_frobenius_norm(tensor) do
    tensor
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
    |> Nx.to_number()
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
  defp to_tensor(other), do: Nx.tensor(other)

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
