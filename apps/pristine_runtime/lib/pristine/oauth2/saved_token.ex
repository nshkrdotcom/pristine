defmodule Pristine.OAuth2.SavedToken do
  @moduledoc """
  Shared persisted-token workflow for OAuth2 token sources.
  """

  alias Pristine.Core.Context
  alias Pristine.OAuth2.{Provider, Token}

  @spec load({module(), keyword()} | module()) :: {:ok, Token.t()} | :error | {:error, term()}
  def load(source) do
    with {:ok, {module, opts}} <- normalize_source(source) do
      normalize_fetch_result(module.fetch(opts))
    end
  end

  @spec save(Token.t(), {module(), keyword()} | module()) :: :ok | {:error, term()}
  def save(%Token{} = token, source) do
    with {:ok, {module, opts}} <- normalize_source(source) do
      module.put(token, opts)
    end
  end

  def save(_token, _source), do: {:error, :invalid_token}

  @spec refresh(Provider.t(), keyword()) :: {:ok, Token.t()} | :error | {:error, term()}
  def refresh(%Provider{} = provider, opts) when is_list(opts) do
    with :ok <- reject_governed_token_source(opts),
         {:ok, source} <- fetch_token_source(opts),
         {:ok, %Token{} = saved_token} <- load(source),
         {:ok, refresh_token} <- fetch_refresh_token(saved_token),
         {:ok, %Token{} = refreshed_token} <-
           oauth2_module(opts).refresh_token(provider, refresh_token, refresh_opts(opts)),
         :ok <- ensure_access_token(refreshed_token),
         merged_token = merge_tokens(saved_token, refreshed_token),
         :ok <- persist(merged_token, source) do
      {:ok, merged_token}
    end
  end

  @spec merge_tokens(Token.t(), Token.t()) :: Token.t()
  def merge_tokens(%Token{} = saved_token, %Token{} = refreshed_token) do
    %Token{
      access_token: refreshed_token.access_token,
      refresh_token: merged_refresh_token(saved_token, refreshed_token),
      expires_at: refreshed_token.expires_at,
      token_type: merged_token_type(saved_token, refreshed_token),
      other_params:
        Map.merge(saved_token.other_params || %{}, refreshed_token.other_params || %{})
    }
  end

  defp fetch_token_source(opts) do
    case Keyword.get(opts, :token_source) || Keyword.get(opts, :source) do
      {module, source_opts} when is_atom(module) and is_list(source_opts) ->
        {:ok, {module, source_opts}}

      module when is_atom(module) ->
        {:ok, {module, []}}

      _other ->
        {:error, :missing_token_source}
    end
  end

  defp reject_governed_token_source(opts) do
    case Keyword.get(opts, :context) do
      %Context{governed_authority: nil} -> :ok
      %Context{} -> {:error, :governed_oauth_token_source_forbidden}
      _other -> :ok
    end
  end

  defp normalize_source({module, opts}) when is_atom(module) and is_list(opts),
    do: {:ok, {module, opts}}

  defp normalize_source(module) when is_atom(module), do: {:ok, {module, []}}
  defp normalize_source(_other), do: {:error, :missing_token_source}

  defp normalize_fetch_result({:ok, %Token{} = token}), do: {:ok, token}
  defp normalize_fetch_result(:error), do: :error
  defp normalize_fetch_result({:error, _reason} = error), do: error
  defp normalize_fetch_result(_other), do: {:error, :invalid_token_source_response}

  defp fetch_refresh_token(%Token{refresh_token: refresh_token})
       when is_binary(refresh_token) and refresh_token != "" do
    {:ok, refresh_token}
  end

  defp fetch_refresh_token(_token), do: {:error, :missing_refresh_token}

  defp ensure_access_token(%Token{access_token: access_token})
       when is_binary(access_token) and access_token != "" do
    :ok
  end

  defp ensure_access_token(_token), do: {:error, :missing_access_token}

  defp merged_refresh_token(_saved_token, %Token{refresh_token: refresh_token})
       when is_binary(refresh_token) and refresh_token != "" do
    refresh_token
  end

  defp merged_refresh_token(%Token{refresh_token: refresh_token}, _refreshed_token) do
    refresh_token
  end

  defp merged_token_type(_saved_token, %Token{token_type: token_type})
       when is_binary(token_type) and token_type != "" do
    token_type
  end

  defp merged_token_type(%Token{token_type: token_type}, _refreshed_token) do
    token_type
  end

  defp refresh_opts(opts) do
    []
    |> maybe_put(:context, Keyword.get(opts, :context))
    |> maybe_put(:client_id, Keyword.get(opts, :client_id))
    |> maybe_put(:client_secret, Keyword.get(opts, :client_secret))
    |> maybe_put(:token_params, normalize_keyword(Keyword.get(opts, :token_params, [])))
  end

  defp oauth2_module(opts) do
    Keyword.get(opts, :oauth2_module, Pristine.OAuth2)
  end

  defp persist(%Token{} = token, source) do
    case save(token, source) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_refresh_persist_failed, reason}}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(value) when is_map(value), do: Enum.into(value, [])
  defp normalize_keyword(_value), do: []
end
