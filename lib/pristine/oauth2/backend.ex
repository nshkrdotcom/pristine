defmodule Pristine.OAuth2.Backend do
  @moduledoc false

  @spec available?() :: boolean()
  def available? do
    implementation().available?()
  end

  @spec new_client(atom(), keyword()) :: {:ok, map()} | {:error, atom()}
  def new_client(strategy, opts) do
    implementation().new_client(strategy, opts)
  end

  @spec authorize_url(map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def authorize_url(client, params) do
    implementation().authorize_url(client, params)
  end

  @spec prepare_token_request(map(), atom(), keyword(), [{String.t(), String.t()}]) ::
          {:ok, map()} | {:error, atom()}
  def prepare_token_request(client, strategy, params, headers) do
    implementation().prepare_token_request(client, strategy, params, headers)
  end

  @spec access_token(map() | String.t()) :: {:ok, map()} | {:error, atom()}
  def access_token(response_body) do
    implementation().access_token(response_body)
  end

  defp implementation do
    Application.get_env(:pristine, :oauth2_backend, Pristine.OAuth2.Backend.OAuth2Lib)
  end
end
