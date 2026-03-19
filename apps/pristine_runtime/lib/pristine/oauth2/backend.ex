defmodule Pristine.OAuth2.Backend do
  @moduledoc false

  alias Pristine.OAuth2.Provider
  alias Pristine.OAuth2.Token
  alias Pristine.Ports.OAuthBackend
  alias Pristine.Ports.OAuthBackend.Request

  @type grant_type :: OAuthBackend.grant_type()
  @type request_kind :: OAuthBackend.request_kind()

  @spec available?() :: boolean()
  def available? do
    implementation().available?()
  end

  @spec authorization_url(Provider.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def authorization_url(%Provider{} = provider, opts) when is_list(opts) do
    implementation().authorization_url(provider, opts)
  end

  @spec build_request(Provider.t(), request_kind(), map() | keyword(), keyword()) ::
          {:ok, Request.t()} | {:error, term()}
  def build_request(%Provider{} = provider, kind, params, opts)
      when is_list(opts) and (is_map(params) or is_list(params)) do
    implementation().build_request(provider, kind, params, opts)
  end

  @spec normalize_token_response(Provider.t(), map() | String.t()) ::
          {:ok, Token.t()} | {:error, term()}
  def normalize_token_response(%Provider{} = provider, body)
      when is_map(body) or is_binary(body) do
    implementation().normalize_token_response(provider, body)
  end

  defp implementation do
    Application.get_env(
      :pristine,
      :oauth_backend,
      Pristine.Adapters.OAuthBackend.Native
    )
  end
end
