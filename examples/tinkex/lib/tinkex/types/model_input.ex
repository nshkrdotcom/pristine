defmodule Tinkex.Types.ModelInput do
  @moduledoc """
  Model input containing chunks of encoded text and/or images.

  Mirrors Python tinker.types.ModelInput.

  ## Note

  The `from_text/2` function requires `Tinkex.Tokenizer` which is not yet
  implemented in this port. Use `from_ints/1` to create inputs from token IDs
  directly.
  """

  alias Tinkex.Types.{EncodedTextChunk, ImageAssetPointerChunk, ImageChunk}

  @derive {Jason.Encoder, only: [:chunks]}
  defstruct chunks: []

  @type chunk ::
          EncodedTextChunk.t()
          | ImageChunk.t()
          | ImageAssetPointerChunk.t()
  @type t :: %__MODULE__{
          chunks: [chunk()]
        }

  @doc """
  Create an empty ModelInput with no chunks.

  ## Examples

      iex> ModelInput.empty()
      %ModelInput{chunks: []}
  """
  @spec empty() :: t()
  def empty, do: %__MODULE__{chunks: []}

  @doc """
  Append a chunk to the ModelInput.

  Returns a new ModelInput with the given chunk appended to the end.

  ## Examples

      iex> input = ModelInput.empty()
      iex> chunk = %EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"}
      iex> ModelInput.append(input, chunk)
      %ModelInput{chunks: [%EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"}]}
  """
  @spec append(t(), chunk()) :: t()
  def append(%__MODULE__{chunks: chunks}, chunk) do
    %__MODULE__{chunks: chunks ++ [chunk]}
  end

  @doc """
  Append a single token to the ModelInput.

  Token-aware append: if the last chunk is an EncodedTextChunk, extends its
  tokens; otherwise adds a new EncodedTextChunk with that single token.

  ## Examples

      iex> input = ModelInput.from_ints([1, 2])
      iex> ModelInput.append_int(input, 3) |> ModelInput.to_ints()
      [1, 2, 3]

      iex> input = ModelInput.empty()
      iex> ModelInput.append_int(input, 42) |> ModelInput.to_ints()
      [42]
  """
  @spec append_int(t(), integer()) :: t()
  def append_int(%__MODULE__{chunks: []}, token) when is_integer(token) do
    %__MODULE__{chunks: [%EncodedTextChunk{tokens: [token], type: "encoded_text"}]}
  end

  def append_int(%__MODULE__{chunks: chunks}, token) when is_integer(token) do
    case List.last(chunks) do
      %EncodedTextChunk{tokens: tokens} = last ->
        updated = %{last | tokens: tokens ++ [token]}
        %__MODULE__{chunks: List.replace_at(chunks, -1, updated)}

      _other ->
        append(%__MODULE__{chunks: chunks}, %EncodedTextChunk{
          tokens: [token],
          type: "encoded_text"
        })
    end
  end

  @doc """
  Create ModelInput from a list of token IDs.
  """
  @spec from_ints([integer()]) :: t()
  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
    }
  end

  @doc """
  Create ModelInput from raw text.

  NOTE: This function requires `Tinkex.Tokenizer` which is not yet implemented.
  Use `from_ints/1` with pre-tokenized input instead.

  Returns `{:error, :tokenizer_not_implemented}` until Tokenizer is available.
  """
  @spec from_text(String.t(), keyword()) :: {:ok, t()} | {:error, atom() | term()}
  def from_text(_text, _opts \\ []) do
    {:error, :tokenizer_not_implemented}
  end

  @doc """
  Create ModelInput from raw text, raising on failure.

  NOTE: This function requires `Tinkex.Tokenizer` which is not yet implemented.
  Raises until Tokenizer is available.
  """
  @spec from_text!(String.t(), keyword()) :: no_return()
  def from_text!(_text, _opts \\ []) do
    raise ArgumentError, "Tokenizer not yet implemented - use from_ints/1 instead"
  end

  @doc """
  Extract all token IDs from the ModelInput.

  Only works with EncodedTextChunk chunks. Raises for image chunks.
  """
  @spec to_ints(t()) :: [integer()]
  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %EncodedTextChunk{tokens: tokens} -> tokens
      _ -> raise ArgumentError, "Cannot convert non-text chunk to ints"
    end)
  end

  @doc """
  Get the total length (token count) of the ModelInput.

  For image chunks, `expected_tokens` must be set; otherwise `length/1` will
  raise to mirror Python SDK guardrails.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, &chunk_length/1))
  end

  defp chunk_length(%EncodedTextChunk{} = chunk), do: EncodedTextChunk.length(chunk)
  defp chunk_length(%ImageChunk{} = chunk), do: ImageChunk.length(chunk)

  defp chunk_length(%ImageAssetPointerChunk{} = chunk),
    do: ImageAssetPointerChunk.length(chunk)
end
