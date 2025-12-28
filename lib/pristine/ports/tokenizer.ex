defmodule Pristine.Ports.Tokenizer do
  @moduledoc """
  Tokenizer boundary for encoding and decoding text.
  """

  @callback encode(String.t(), keyword()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  @callback decode([non_neg_integer()], keyword()) :: {:ok, String.t()} | {:error, term()}
end
