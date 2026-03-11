defmodule Pristine.Ports.TokenSource do
  @moduledoc """
  Boundary for retrieving and storing OAuth2 tokens.
  """

  alias Pristine.OAuth2.Token

  @callback fetch(keyword()) :: {:ok, Token.t()} | :error | {:error, term()}
  @callback put(Token.t(), keyword()) :: :ok | {:error, term()}
end
