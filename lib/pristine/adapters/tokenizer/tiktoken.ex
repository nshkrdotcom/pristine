defmodule Pristine.Adapters.Tokenizer.Tiktoken do
  @moduledoc """
  Tokenizer adapter backed by TiktokenEx encodings.
  """

  @behaviour Pristine.Ports.Tokenizer

  alias TiktokenEx.Encoding

  @impl true
  def encode(text, opts) do
    with {:ok, encoding} <- fetch_encoding(opts) do
      Encoding.encode(encoding, text)
    end
  end

  @impl true
  def decode(tokens, opts) do
    with {:ok, encoding} <- fetch_encoding(opts) do
      Encoding.decode(encoding, tokens)
    end
  end

  defp fetch_encoding(opts) do
    case Keyword.fetch(opts, :encoding) do
      {:ok, encoding} -> {:ok, encoding}
      :error -> {:error, :missing_encoding}
    end
  end
end
