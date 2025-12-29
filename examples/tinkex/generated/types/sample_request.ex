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
          stop_sequences: [String.t()] | nil,
          stream: boolean() | nil,
          temperature: number() | nil,
          top_p: number() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:max_tokens, :integer,
       [description: "Maximum tokens to generate", default: 1024, optional: true]},
      {:metadata, :any, [description: "Custom metadata to attach", optional: true]},
      {:model, :string, [description: "Model ID to use", required: true]},
      {:prompt, :string, [description: "Input prompt", required: true]},
      {:stop_sequences, {:array, :string},
       [description: "Sequences that stop generation", optional: true]},
      {:stream, :boolean, [description: "Whether to stream the response", optional: true]},
      {:temperature, :float, [description: "Sampling temperature", default: 1.0, optional: true]},
      {:top_p, :float, [description: "Nucleus sampling parameter", optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Types.SampleRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         max_tokens: validated["max_tokens"],
         metadata: validated["metadata"],
         model: validated["model"],
         prompt: validated["prompt"],
         stop_sequences: validated["stop_sequences"],
         stream: validated["stream"],
         temperature: validated["temperature"],
         top_p: validated["top_p"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Types.SampleRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "max_tokens" => struct.max_tokens,
      "metadata" => struct.metadata,
      "model" => struct.model,
      "prompt" => struct.prompt,
      "stop_sequences" => struct.stop_sequences,
      "stream" => struct.stream,
      "temperature" => struct.temperature,
      "top_p" => struct.top_p
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Types.SampleRequest from a map."
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

  @doc "Create a new Tinkex.Types.SampleRequest."
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
