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

  @doc """
  Convert a Tinkex dtype to an Nx tensor type.

  ## Examples

      iex> TensorDtype.to_nx_type(:int64)
      :s64

      iex> TensorDtype.to_nx_type(:float32)
      :f32
  """
  @spec to_nx_type(t()) :: atom()
  def to_nx_type(:int64), do: :s64
  def to_nx_type(:float32), do: :f32

  @doc """
  Convert an Nx tensor type to a Tinkex dtype.

  Handles both the new tuple format `{:f, 32}` and legacy atom format `:f32`.

  ## Examples

      iex> TensorDtype.from_nx_type({:s, 64})
      :int64

      iex> TensorDtype.from_nx_type({:f, 32})
      :float32
  """
  @spec from_nx_type(atom() | {atom(), non_neg_integer()}) :: t()
  def from_nx_type({:s, 64}), do: :int64
  def from_nx_type({:s, 32}), do: :int64
  def from_nx_type({:s, _}), do: :int64
  def from_nx_type({:f, 32}), do: :float32
  def from_nx_type({:f, 64}), do: :float32
  def from_nx_type({:f, _}), do: :float32
  def from_nx_type({:u, _}), do: :int64
  # Legacy atom format (for backwards compatibility)
  def from_nx_type(:s64), do: :int64
  def from_nx_type(:s32), do: :int64
  def from_nx_type(:f32), do: :float32
  def from_nx_type(:f64), do: :float32
end
