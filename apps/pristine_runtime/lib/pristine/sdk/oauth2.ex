defmodule Pristine.SDK.OAuth2 do
  @moduledoc """
  SDK-facing OAuth2 control-plane helpers.
  """

  alias Pristine.OAuth2, as: RuntimeOAuth2
  alias Pristine.SDK.OAuth2.{AuthorizationRequest, Error, Provider, Token}

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec available?() :: boolean()
  defdelegate available?(), to: RuntimeOAuth2

  @spec authorization_request(Provider.t(), keyword()) :: result(AuthorizationRequest.t())
  defdelegate authorization_request(provider, opts \\ []), to: RuntimeOAuth2

  @spec authorize_url(Provider.t(), keyword()) :: result(String.t())
  defdelegate authorize_url(provider, opts \\ []), to: RuntimeOAuth2

  @spec exchange_code(Provider.t(), String.t(), keyword()) :: result(Token.t())
  defdelegate exchange_code(provider, code, opts \\ []), to: RuntimeOAuth2

  @spec refresh_token(Provider.t(), String.t(), keyword()) :: result(Token.t())
  defdelegate refresh_token(provider, refresh_token, opts \\ []), to: RuntimeOAuth2

  @spec client_credentials(Provider.t(), keyword()) :: result(Token.t())
  defdelegate client_credentials(provider, opts \\ []), to: RuntimeOAuth2

  @spec password_token(Provider.t(), String.t(), String.t(), keyword()) :: result(Token.t())
  defdelegate password_token(provider, username, password, opts \\ []), to: RuntimeOAuth2

  @spec revoke_token(Provider.t(), String.t(), keyword()) :: result(map())
  defdelegate revoke_token(provider, token, opts \\ []), to: RuntimeOAuth2

  @spec introspect_token(Provider.t(), String.t(), keyword()) :: result(map())
  defdelegate introspect_token(provider, token, opts \\ []), to: RuntimeOAuth2
end
