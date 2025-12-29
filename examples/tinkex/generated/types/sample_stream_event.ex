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
      {:content_block, :any, [description: "Content block data", optional: true]},
      {:delta, :any, [description: "Delta update", optional: true]},
      {:error, :any, [description: "Error details", optional: true]},
      {:index, :integer, [description: "Content block index", optional: true]},
      {:message, :any, [description: "Partial message (for message_start)", optional: true]},
      {:type, :string,
       [
         choices: [
           "message_start",
           "content_block_start",
           "content_block_delta",
           "content_block_stop",
           "message_delta",
           "message_stop",
           "ping",
           "error"
         ],
         required: true
       ]},
      {:usage, :any, [description: "Usage information", optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Types.SampleStreamEvent struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         content_block: validated["content_block"],
         delta: validated["delta"],
         error: validated["error"],
         index: validated["index"],
         message: validated["message"],
         type: validated["type"],
         usage: validated["usage"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Types.SampleStreamEvent struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "content_block" => struct.content_block,
      "delta" => struct.delta,
      "error" => struct.error,
      "index" => struct.index,
      "message" => struct.message,
      "type" => struct.type,
      "usage" => struct.usage
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.SampleStreamEvent from a map."
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

  @doc "Create a new Tinkex.Types.SampleStreamEvent."
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
