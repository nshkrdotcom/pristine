defmodule Pristine.Adapters.Auth.OAuth2 do
  @moduledoc """
  OAuth2 bearer adapter backed by a token source.
  """

  @behaviour Pristine.Ports.Auth

  alias Pristine.OAuth2.Token

  @spec new(keyword()) :: {module(), keyword()}
  def new(opts \\ []) when is_list(opts) do
    {__MODULE__, opts}
  end

  @impl true
  def headers(opts) do
    with {:ok, token} <- fetch_token(opts),
         :ok <- ensure_fresh(token, opts),
         {:ok, access_token} <- access_token(token) do
      {:ok, %{"Authorization" => "Bearer #{access_token}"}}
    end
  end

  defp fetch_token(opts) do
    case Keyword.fetch(opts, :token_source) do
      {:ok, {module, token_opts}} when is_atom(module) and is_list(token_opts) ->
        normalize_fetch_result(module.fetch(token_opts))

      {:ok, module} when is_atom(module) ->
        normalize_fetch_result(module.fetch([]))

      :error ->
        {:error, :missing_token_source}
    end
  end

  defp normalize_fetch_result({:ok, %Token{} = token}), do: {:ok, token}
  defp normalize_fetch_result(:error), do: {:error, :missing_oauth2_token}
  defp normalize_fetch_result({:error, _reason} = error), do: error
  defp normalize_fetch_result(_other), do: {:error, :missing_oauth2_token}

  defp ensure_fresh(%Token{} = token, opts) do
    if Keyword.get(opts, :allow_stale?, false) or not Token.expired?(token) do
      :ok
    else
      {:error, :expired_oauth2_token}
    end
  end

  defp access_token(%Token{access_token: token}) when is_binary(token) and token != "",
    do: {:ok, token}

  defp access_token(_token), do: {:error, :missing_oauth2_access_token}
end
