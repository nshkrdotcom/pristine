defmodule Tinkex.Types.SampleStreamEvent do
  @moduledoc """
  SampleStreamEvent type.
  """

  defstruct [:content_block, :delta, :error, :index, :message, :type, :usage]

  @type t :: %__MODULE__{
          content_block: term() | nil,
          delta: term() | nil,
          error: term() | nil,
          index: integer() | nil,
          message: term() | nil,
          type: String.t(),
          usage: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:content_block, :any, [optional: true]},
      {:delta, :any, [optional: true]},
      {:error, :any, [optional: true]},
      {:index, :integer, [optional: true]},
      {:message, :any, [optional: true]},
      {:type, :string, [required: true]},
      {:usage, :any, [optional: true]}
    ])
  end

  @doc "Create a new SampleStreamEvent from a map."
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

  @doc "Create a new SampleStreamEvent."
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
