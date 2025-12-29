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
      {:id, :string, [description: "Tool use ID (for tool_use blocks)", optional: true]},
      {:input, :any, [description: "Tool input (for tool_use blocks)", optional: true]},
      {:name, :string, [description: "Tool name (for tool_use blocks)", optional: true]},
      {:text, :string, [description: "Text content (for text blocks)", optional: true]},
      {:type, :string, [choices: ["text", "tool_use"], required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Types.ContentBlock struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         id: validated["id"],
         input: validated["input"],
         name: validated["name"],
         text: validated["text"],
         type: validated["type"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Types.ContentBlock struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "id" => struct.id,
      "input" => struct.input,
      "name" => struct.name,
      "text" => struct.text,
      "type" => struct.type
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.ContentBlock from a map."
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

  @doc "Create a new Tinkex.Types.ContentBlock."
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
