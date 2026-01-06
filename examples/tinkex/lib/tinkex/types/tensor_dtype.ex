defmodule Tinkex.Types.TensorDtype do
  @moduledoc """
  Tensor data type enumeration.

  Mirrors Python tinker.types.TensorDtype.

  Only two dtypes are supported by the backend:
  - `:int64` - 64-bit signed integers
  - `:float32` - 32-bit floating point
  """

  @type t :: :int64 | :float32

  @dtypes [:int64, :float32]

  @doc """
  Returns all supported tensor dtypes.

  ## Examples

      iex> TensorDtype.values()
      [:int64, :float32]
  """
  @spec values() :: [t()]
  def values, do: @dtypes

  @doc """
  Check if a value is a valid tensor dtype.

  ## Examples

      iex> TensorDtype.valid?(:int64)
      true

      iex> TensorDtype.valid?(:float64)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(dtype), do: dtype in @dtypes

  @doc """
  Parse a wire format string to a dtype atom.

  Returns `nil` for unrecognized types.

  ## Examples

      iex> TensorDtype.parse("int64")
      :int64

      iex> TensorDtype.parse("float64")
      nil
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("int64"), do: :int64
  def parse("float32"), do: :float32
  def parse(_), do: nil

  @doc """
  Convert a dtype atom to wire format string.

  ## Examples

      iex> TensorDtype.to_string(:int64)
      "int64"
  """
  @spec to_string(t()) :: String.t()
  def to_string(:int64), do: "int64"
  def to_string(:float32), do: "float32"
end
