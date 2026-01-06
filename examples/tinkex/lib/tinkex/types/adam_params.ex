defmodule Tinkex.Types.AdamParams do
  @moduledoc """
  Adam optimizer parameters for training.

  Mirrors Python tinker.types.AdamParams.

  ## Fields

  - `learning_rate` - Learning rate (default: 0.0001)
  - `beta1` - Exponential decay rate for 1st moment (default: 0.9)
  - `beta2` - Exponential decay rate for 2nd moment (default: 0.95, not 0.999!)
  - `eps` - Small constant for numerical stability (default: 1e-12, not 1e-8!)
  - `weight_decay` - L2 regularization coefficient (default: 0.0)
  - `grad_clip_norm` - Gradient clipping threshold, 0 = disabled (default: 0.0)

  Note: Defaults exactly match Python SDK for parity.
  """

  @derive {Jason.Encoder,
           only: [:learning_rate, :beta1, :beta2, :eps, :weight_decay, :grad_clip_norm]}
  defstruct learning_rate: 0.0001,
            beta1: 0.9,
            beta2: 0.95,
            eps: 1.0e-12,
            weight_decay: 0.0,
            grad_clip_norm: 0.0

  @type t :: %__MODULE__{
          learning_rate: float(),
          beta1: float(),
          beta2: float(),
          eps: float(),
          weight_decay: float(),
          grad_clip_norm: float()
        }

  @doc """
  Create AdamParams with validation.

  ## Options

  - `:learning_rate` - Must be > 0
  - `:beta1` - Must be in [0, 1)
  - `:beta2` - Must be in [0, 1)
  - `:eps` - Must be > 0
  - `:weight_decay` - Must be >= 0
  - `:grad_clip_norm` - Must be >= 0

  ## Examples

      iex> AdamParams.new()
      {:ok, %AdamParams{learning_rate: 0.0001, ...}}

      iex> AdamParams.new(learning_rate: 0.001)
      {:ok, %AdamParams{learning_rate: 0.001, ...}}

      iex> AdamParams.new(learning_rate: -1)
      {:error, "learning_rate must be > 0"}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts \\ []) do
    params = struct(__MODULE__, opts)

    with :ok <- validate_learning_rate(params.learning_rate),
         :ok <- validate_beta(:beta1, params.beta1),
         :ok <- validate_beta(:beta2, params.beta2),
         :ok <- validate_epsilon(params.eps),
         :ok <- validate_non_negative(:weight_decay, params.weight_decay),
         :ok <- validate_non_negative(:grad_clip_norm, params.grad_clip_norm) do
      {:ok, params}
    end
  end

  defp validate_learning_rate(lr) when is_number(lr) and lr > 0, do: :ok
  defp validate_learning_rate(_), do: {:error, "learning_rate must be > 0"}

  defp validate_beta(name, value) when is_number(value) and value >= 0 and value < 1, do: :ok
  defp validate_beta(name, _), do: {:error, "#{name} must be in range [0, 1)"}

  defp validate_epsilon(eps) when is_number(eps) and eps > 0, do: :ok
  defp validate_epsilon(_), do: {:error, "eps must be > 0"}

  defp validate_non_negative(name, value) when is_number(value) and value >= 0, do: :ok
  defp validate_non_negative(name, _), do: {:error, "#{name} must be >= 0"}
end
