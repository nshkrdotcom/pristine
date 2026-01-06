defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type enumeration for training operations.

  Supported loss functions:
  - `:cross_entropy` - Standard cross-entropy loss
  - `:importance_sampling` - Importance-weighted sampling loss
  - `:ppo` - Proximal Policy Optimization loss
  - `:cispo` - Constrained Importance Sampling Policy Optimization loss
  - `:dro` - Distributionally Robust Optimization loss
  - `:linear_weighted` - Linear weighted loss (used for custom loss gradients)
  """

  @type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro | :linear_weighted

  @values [:cross_entropy, :importance_sampling, :ppo, :cispo, :dro, :linear_weighted]

  @doc """
  Returns all valid loss function types.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Parses a wire format string into a loss function atom.

  Returns nil for nil input.

  ## Examples

      iex> LossFnType.parse("cross_entropy")
      :cross_entropy

      iex> LossFnType.parse(nil)
      nil
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse(nil), do: nil
  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse("cispo"), do: :cispo
  def parse("dro"), do: :dro
  def parse("linear_weighted"), do: :linear_weighted

  @doc """
  Converts a loss function atom to its wire format string.

  ## Examples

      iex> LossFnType.to_string(:cross_entropy)
      "cross_entropy"
  """
  @spec to_string(t()) :: String.t()
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"
  def to_string(:cispo), do: "cispo"
  def to_string(:dro), do: "dro"
  def to_string(:linear_weighted), do: "linear_weighted"
end
