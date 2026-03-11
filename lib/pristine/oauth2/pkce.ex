defmodule Pristine.OAuth2.PKCE do
  @moduledoc false

  @spec generate(pos_integer()) :: String.t()
  def generate(length \\ 32) when is_integer(length) and length > 0 do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec challenge(String.t(), :plain | :s256) :: String.t()
  def challenge(verifier, :plain), do: verifier

  def challenge(verifier, :s256) do
    verifier
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
