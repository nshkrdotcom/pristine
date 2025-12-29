defmodule Tinkex.Types.ModelList do
  @moduledoc """
  ModelList type.
  """

  defstruct [:data, :has_more, :next_cursor]

  @type t :: %__MODULE__{
          data: [Tinkex.Types.Model.t()],
          has_more: boolean(),
          next_cursor: String.t() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:data, {:array, {:object, Tinkex.Types.Model.schema()}}, [required: true]},
      {:has_more, :boolean, [required: true]},
      {:next_cursor, :string, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Types.ModelList struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         data: validated["data"],
         has_more: validated["has_more"],
         next_cursor: validated["next_cursor"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Types.ModelList struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "data" => struct.data,
      "has_more" => struct.has_more,
      "next_cursor" => struct.next_cursor
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.ModelList from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    struct(__MODULE__, atomize_keys(data))
  end

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.ModelList."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
