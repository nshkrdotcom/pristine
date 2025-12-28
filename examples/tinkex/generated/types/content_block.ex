defmodule Tinkex.Types.ContentBlock do
  @moduledoc """
  ContentBlock type.
  """

  defstruct [:id, :input, :name, :text, :type]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          input: term() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          type: String.t()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:id, :string, [optional: true]},
      {:input, :any, [optional: true]},
      {:name, :string, [optional: true]},
      {:text, :string, [optional: true]},
      {:type, :string, [required: true]}
    ])
  end

  @doc "Create a new ContentBlock from a map."
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

  @doc "Create a new ContentBlock."
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
