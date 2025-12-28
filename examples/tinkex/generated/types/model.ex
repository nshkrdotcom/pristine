defmodule Tinkex.Types.Model do
  @moduledoc """
  Model type.
  """

  defstruct [:capabilities, :context_length, :created_at, :description, :id, :name]

  @type t :: %__MODULE__{
          capabilities: list() | nil,
          context_length: integer(),
          created_at: String.t() | nil,
          description: String.t() | nil,
          id: String.t(),
          name: String.t()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:capabilities, {:array, :any}, [optional: true]},
      {:context_length, :integer, [required: true]},
      {:created_at, :string, [optional: true]},
      {:description, :string, [optional: true]},
      {:id, :string, [required: true]},
      {:name, :string, [required: true]}
    ])
  end

  @doc "Create a new Model from a map."
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

  @doc "Create a new Model."
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
