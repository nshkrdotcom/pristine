defmodule Pristine.Adapters.TokenizerTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Tokenizer.Tiktoken

  test "returns error when encoding is missing" do
    assert {:error, :missing_encoding} = Tiktoken.encode("hello", [])
    assert {:error, :missing_encoding} = Tiktoken.decode([1, 2], [])
  end

  test "returns error when the tiktoken dependency is unavailable" do
    opts = [encoding: "cl100k_base", encoding_module: MissingEncoding]

    assert {:error, :tiktoken_unavailable} = Tiktoken.encode("hello", opts)
    assert {:error, :tiktoken_unavailable} = Tiktoken.decode([1, 2], opts)
  end
end
