defmodule Pristine.Adapters.TokenizerTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Tokenizer.Tiktoken

  test "returns error when encoding is missing" do
    assert {:error, :missing_encoding} = Tiktoken.encode("hello", [])
    assert {:error, :missing_encoding} = Tiktoken.decode([1, 2], [])
  end
end
