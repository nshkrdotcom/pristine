defmodule Pristine.Adapters.Tokenizer.Tiktoken do
  @moduledoc """
  Tokenizer adapter backed by TiktokenEx encodings.
  """

  @behaviour Pristine.Ports.Tokenizer
  @compile {:no_warn_undefined, [TiktokenEx.Encoding]}

  @impl true
  def encode(text, opts) do
    with {:ok, encoding} <- fetch_encoding(opts),
         {:ok, encoding_module} <- fetch_encoding_module(opts) do
      encoding_module.encode(encoding, text, [])
    end
  end

  @impl true
  def decode(tokens, opts) do
    with {:ok, encoding} <- fetch_encoding(opts),
         {:ok, encoding_module} <- fetch_encoding_module(opts) do
      encoding_module.decode(encoding, tokens)
    end
  end

  defp fetch_encoding(opts) do
    case Keyword.fetch(opts, :encoding) do
      {:ok, encoding} -> {:ok, encoding}
      :error -> {:error, :missing_encoding}
    end
  end

  defp fetch_encoding_module(opts) do
    encoding_module =
      Keyword.get(
        opts,
        :encoding_module,
        Application.get_env(:pristine, :tiktoken_encoding_module, TiktokenEx.Encoding)
      )

    if Code.ensure_loaded?(encoding_module) and function_exported?(encoding_module, :encode, 3) and
         function_exported?(encoding_module, :decode, 2) do
      {:ok, encoding_module}
    else
      {:error, :tiktoken_unavailable}
    end
  end
end
