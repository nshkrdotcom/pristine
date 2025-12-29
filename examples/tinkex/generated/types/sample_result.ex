defmodule Tinkex.Types.SampleResult do
  @moduledoc """
  SampleResult type.
  """

  defstruct [:content, :created_at, :id, :model, :stop_reason, :usage]

  @type t :: %__MODULE__{
          content: [Tinkex.Types.ContentBlock.t()],
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
      {:content, {:array, {:object, Tinkex.Types.ContentBlock.schema()}},
       [description: "Generated content blocks", required: true]},
      {:created_at, :string, [required: true]},
      {:id, :string, [description: "Unique sample ID", required: true]},
      {:model, :string, [description: "Model used", required: true]},
      {:stop_reason, :string,
       [
         choices: ["end_turn", "max_tokens", "stop_sequence", "tool_use"],
         description: "Why generation stopped",
         required: true
       ]},
      {:usage, :any, [description: "Token usage information", required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Types.SampleResult struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         content: validated["content"],
         created_at: validated["created_at"],
         id: validated["id"],
         model: validated["model"],
         stop_reason: validated["stop_reason"],
         usage: validated["usage"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Types.SampleResult struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "content" => struct.content,
      "created_at" => struct.created_at,
      "id" => struct.id,
      "model" => struct.model,
      "stop_reason" => struct.stop_reason,
      "usage" => struct.usage
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.SampleResult from a map."
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

  @doc "Create a new Tinkex.Types.SampleResult."
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
