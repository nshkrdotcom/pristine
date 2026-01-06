defmodule Tinkex.Types.TensorData do
  @moduledoc """
  Container for tensor data with dtype and shape information.

  Mirrors Python tinker.types.TensorData.

  ## Fields

  - `data` - Flat list of numerical values
  - `dtype` - Data type (`:int64` or `:float32`)
  - `shape` - Tensor shape as list; `nil` for scalar/flat

  ## Note

  The `from_nx/1` and `to_nx/1` functions require Nx which is not yet
  a dependency. Use `new/3` to create TensorData directly from lists.
  """

  alias Tinkex.Types.TensorDtype

  defstruct [:data, :dtype, :shape]

  @type t :: %__MODULE__{
          data: [number()],
          dtype: TensorDtype.t(),
          shape: [non_neg_integer()] | nil
        }

  @doc """
  Create TensorData from a data list, dtype, and optional shape.

  ## Examples

      iex> TensorData.new([1.0, 2.0, 3.0], :float32, [3])
      %TensorData{data: [1.0, 2.0, 3.0], dtype: :float32, shape: [3]}

      iex> TensorData.new([1, 2], :int64)
      %TensorData{data: [1, 2], dtype: :int64, shape: nil}
  """
  @spec new([number()], TensorDtype.t(), [non_neg_integer()] | nil) :: t()
  def new(data, dtype, shape \\ nil) when is_list(data) and is_atom(dtype) do
    %__MODULE__{data: data, dtype: dtype, shape: shape}
  end

  @doc """
  Returns the flat data list.

  Provides API parity with Python's TensorData.tolist().

  ## Examples

      iex> tensor = TensorData.new([1, 2, 3], :int64, [3])
      iex> TensorData.tolist(tensor)
      [1, 2, 3]
  """
  @spec tolist(t()) :: [number()]
  def tolist(%__MODULE__{data: data}), do: data

  @doc """
  Create TensorData from a decoded JSON map.

  ## Examples

      iex> TensorData.from_map(%{"data" => [1, 2], "dtype" => "int64", "shape" => [2]})
      %TensorData{data: [1, 2], dtype: :int64, shape: [2]}
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      data: Map.get(map, "data"),
      dtype: TensorDtype.parse(Map.get(map, "dtype")),
      shape: Map.get(map, "shape")
    }
  end

  @doc """
  Convert an Nx tensor to TensorData.

  ## Examples

      iex> tensor = Nx.tensor([1.0, 2.0, 3.0])
      iex> TensorData.from_nx(tensor)
      %TensorData{data: [1.0, 2.0, 3.0], dtype: :float32, shape: [3]}
  """
  @spec from_nx(Nx.Tensor.t()) :: t()
  def from_nx(%Nx.Tensor{} = tensor) do
    data = Nx.to_flat_list(tensor)
    shape = Nx.shape(tensor) |> Tuple.to_list()
    nx_type = Nx.type(tensor)
    dtype = TensorDtype.from_nx_type(nx_type)

    %__MODULE__{
      data: data,
      dtype: dtype,
      shape: shape
    }
  end

  @doc """
  Convert TensorData to an Nx tensor.

  ## Examples

      iex> td = TensorData.new([1.0, 2.0, 3.0], :float32, [3])
      iex> TensorData.to_nx(td)
      #Nx.Tensor<f32[3]>
  """
  @spec to_nx(t()) :: Nx.Tensor.t()
  def to_nx(%__MODULE__{data: data, dtype: dtype, shape: shape}) do
    nx_type = TensorDtype.to_nx_type(dtype)
    tensor = Nx.tensor(data, type: nx_type)

    case shape do
      nil -> tensor
      [] -> tensor
      shape_list -> Nx.reshape(tensor, List.to_tuple(shape_list))
    end
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.TensorData do
  alias Tinkex.Types.TensorDtype

  def encode(tensor, opts) do
    %{
      data: tensor.data,
      dtype: TensorDtype.to_string(tensor.dtype),
      shape: tensor.shape
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end
