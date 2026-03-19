defmodule Pristine.Ports.OAuthBackend do
  @moduledoc """
  Boundary for OAuth control-plane request shaping and token normalization.
  """

  alias Pristine.OAuth2.{Provider, Token}
  alias Pristine.Ports.OAuthBackend.Request

  @type grant_type :: :authorization_code | :refresh_token | :client_credentials | :password
  @type request_kind :: {:token, grant_type()} | :revoke | :introspect

  @callback available?() :: boolean()
  @callback authorization_url(Provider.t(), keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback build_request(Provider.t(), request_kind(), map() | keyword(), keyword()) ::
              {:ok, Request.t()} | {:error, term()}
  @callback normalize_token_response(Provider.t(), map() | String.t()) ::
              {:ok, Token.t()} | {:error, term()}
end
