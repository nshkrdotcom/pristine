defmodule Pristine.OAuth2.Backend.OAuth2Lib do
  @moduledoc false

  @spec available?() :: boolean()
  def available? do
    Enum.all?(
      [
        client_module(),
        access_token_module(),
        strategy_module(:authorization_code),
        strategy_module(:refresh_token),
        strategy_module(:client_credentials),
        strategy_module(:password)
      ],
      &Code.ensure_loaded?/1
    )
  end

  @spec new_client(atom(), keyword()) :: {:ok, map()} | {:error, atom()}
  def new_client(strategy, opts) do
    with_available(fn ->
      {:ok,
       apply(client_module(), :new, [Keyword.put(opts, :strategy, strategy_module(strategy))])}
    end)
  end

  @spec authorize_url(map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def authorize_url(client, params) do
    with_available(fn ->
      {_client, url} = apply(client_module(), :authorize_url, [client, params])
      {:ok, url}
    end)
  end

  @spec prepare_token_request(map(), atom(), keyword(), [{String.t(), String.t()}]) ::
          {:ok, map()} | {:error, atom()}
  def prepare_token_request(client, strategy, params, headers) do
    with_available(fn ->
      {:ok, apply(strategy_module(strategy), :get_token, [client, params, headers])}
    end)
  end

  @spec access_token(map() | String.t()) :: {:ok, map()} | {:error, atom()}
  def access_token(response_body) do
    with_available(fn ->
      {:ok, apply(access_token_module(), :new, [response_body])}
    end)
  end

  defp with_available(fun) do
    if available?() do
      fun.()
    else
      {:error, :oauth2_unavailable}
    end
  end

  defp client_module, do: Module.concat([OAuth2, Client])
  defp access_token_module, do: Module.concat([OAuth2, AccessToken])
  defp strategy_module(:authorization_code), do: Module.concat([OAuth2, Strategy, AuthCode])
  defp strategy_module(:refresh_token), do: Module.concat([OAuth2, Strategy, Refresh])

  defp strategy_module(:client_credentials),
    do: Module.concat([OAuth2, Strategy, ClientCredentials])

  defp strategy_module(:password), do: Module.concat([OAuth2, Strategy, Password])
end
