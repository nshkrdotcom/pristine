defmodule Tinkex.Types.SampleResult do
  @moduledoc """
  SampleResult type.
  """

  defstruct [:content, :created_at, :id, :model, :stop_reason, :usage]

  @type t :: %__MODULE__{
          content: list(),
          created_at: String.t(),
          id: String.t(),
          model: String.t(),
          stop_reason: String.t(),
          usage: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:content, {:array, :any}, [required: true]},
      {:created_at, :string, [required: true]},
      {:id, :string, [required: true]},
      {:model, :string, [required: true]},
      {:stop_reason, :string, [required: true]},
      {:usage, :any, [required: true]}
    ])
  end

  @doc "Create a new SampleResult from a map."
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

  @doc "Create a new SampleResult."
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
