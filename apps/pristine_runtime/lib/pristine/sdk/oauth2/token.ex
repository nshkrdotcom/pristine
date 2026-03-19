defmodule Pristine.SDK.OAuth2.Token do
  @moduledoc """
  SDK-facing OAuth2 token contract.
  """

  alias Pristine.OAuth2.Token, as: RuntimeToken

  @type t :: RuntimeToken.t()

  @spec from_backend_token(map()) :: t()
  defdelegate from_backend_token(token), to: RuntimeToken

  @spec to_map(t()) :: map()
  defdelegate to_map(token), to: RuntimeToken

  @spec from_map(map()) :: t()
  defdelegate from_map(token), to: RuntimeToken

  @spec expires?(t()) :: boolean()
  defdelegate expires?(token), to: RuntimeToken

  @spec expired?(t()) :: boolean()
  defdelegate expired?(token), to: RuntimeToken
end
