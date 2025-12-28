defmodule Tinkex.Types.SampleRequest do
  @moduledoc """
  SampleRequest type.
  """

  defstruct [
    :max_tokens,
    :metadata,
    :model,
    :prompt,
    :stop_sequences,
    :stream,
    :temperature,
    :top_p
  ]

  @type t :: %__MODULE__{
          max_tokens: integer() | nil,
          metadata: term() | nil,
          model: String.t(),
          prompt: String.t(),
          stop_sequences: list() | nil,
          stream: boolean() | nil,
          temperature: number() | nil,
          top_p: number() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:max_tokens, :integer, [optional: true]},
      {:metadata, :any, [optional: true]},
      {:model, :string, [required: true]},
      {:prompt, :string, [required: true]},
      {:stop_sequences, {:array, :any}, [optional: true]},
      {:stream, :boolean, [optional: true]},
      {:temperature, :float, [optional: true]},
      {:top_p, :float, [optional: true]}
    ])
  end

  @doc "Create a new SampleRequest from a map."
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

  @doc "Create a new SampleRequest."
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
