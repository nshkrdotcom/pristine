defmodule Pristine.Adapters.TokenSource.Refreshable do
  @moduledoc """
  Token source wrapper that refreshes expiring OAuth2 tokens through `Pristine.OAuth2`.

  Options:

  - `:inner_source` - required wrapped token source as `{module, keyword()}` or `module`
  - `:provider` - required `Pristine.OAuth2.Provider`
  - `:context` - Pristine context used for the refresh request
  - `:client_id` - OAuth client id for the refresh request
  - `:client_secret` - OAuth client secret for the refresh request
  - `:token_params` - extra provider-specific refresh params
  - `:refresh_skew_seconds` - refresh before expiry by this many seconds

  The wrapper only attempts refresh when the current token has a real
  `expires_at` value. If the provider returns a replacement refresh token, the
  wrapper persists that rotated value back through the wrapped token source.
  """

  @behaviour Pristine.Ports.TokenSource

  alias Pristine.Core.Context
  alias Pristine.OAuth2
  alias Pristine.OAuth2.{Provider, SavedToken, Token}

  @impl true
  def fetch(opts) do
    with :ok <- reject_governed_token_source(opts),
         {:ok, {source_module, source_opts}} <- fetch_inner_source(opts),
         {:ok, %Token{} = token} <- normalize_fetch_result(source_module.fetch(source_opts)) do
      maybe_refresh(token, source_module, source_opts, opts)
    end
  end

  @impl true
  def put(%Token{} = token, opts) do
    with {:ok, {source_module, source_opts}} <- fetch_inner_source(opts) do
      source_module.put(token, source_opts)
    end
  end

  def put(_token, _opts), do: {:error, :invalid_token}

  defp maybe_refresh(%Token{expires_at: nil} = token, _source_module, _source_opts, _opts) do
    {:ok, token}
  end

  defp maybe_refresh(%Token{} = token, source_module, source_opts, opts) do
    if refresh_needed?(token, opts) do
      refresh_and_persist(token, source_module, source_opts, opts)
    else
      {:ok, token}
    end
  end

  defp refresh_and_persist(%Token{} = current_token, source_module, source_opts, opts) do
    with {:ok, %Provider{} = provider} <- fetch_provider(opts),
         {:ok, refresh_token} <- fetch_refresh_token(current_token),
         {:ok, %Token{} = refreshed_token} <-
           oauth2_module(opts).refresh_token(provider, refresh_token, refresh_opts(opts)),
         :ok <- ensure_access_token(refreshed_token),
         merged_token = SavedToken.merge_tokens(current_token, refreshed_token),
         :ok <- persist_token(source_module, source_opts, merged_token) do
      {:ok, merged_token}
    end
  end

  defp refresh_needed?(%Token{expires_at: expires_at}, opts) when is_integer(expires_at) do
    System.system_time(:second) + refresh_skew_seconds(opts) >= expires_at
  end

  defp refresh_needed?(_token, _opts), do: false

  defp fetch_inner_source(opts) do
    case Keyword.get(opts, :inner_source) || Keyword.get(opts, :token_source) do
      {module, source_opts} when is_atom(module) and is_list(source_opts) ->
        {:ok, {module, source_opts}}

      module when is_atom(module) ->
        {:ok, {module, []}}

      _other ->
        {:error, :missing_inner_token_source}
    end
  end

  defp reject_governed_token_source(opts) do
    case Keyword.get(opts, :context) do
      %Context{governed_authority: nil} -> :ok
      %Context{} -> {:error, :governed_oauth_token_source_forbidden}
      _other -> :ok
    end
  end

  defp fetch_provider(opts) do
    case Keyword.get(opts, :provider) do
      %Provider{} = provider -> {:ok, provider}
      _other -> {:error, :missing_provider}
    end
  end

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

  defp persist_token(source_module, source_opts, %Token{} = token) do
    case source_module.put(token, source_opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_refresh_persist_failed, reason}}
    end
  end

  defp refresh_opts(opts) do
    []
    |> maybe_put(:context, Keyword.get(opts, :context))
    |> maybe_put(:client_id, Keyword.get(opts, :client_id))
    |> maybe_put(:client_secret, Keyword.get(opts, :client_secret))
    |> maybe_put(:token_params, normalize_keyword(Keyword.get(opts, :token_params, [])))
  end

  defp oauth2_module(opts) do
    Keyword.get(opts, :oauth2_module, OAuth2)
  end

  defp refresh_skew_seconds(opts) do
    case Keyword.get(opts, :refresh_skew_seconds, 0) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 0
    end
  end

  defp normalize_fetch_result({:ok, %Token{} = token}), do: {:ok, token}
  defp normalize_fetch_result(:error), do: :error
  defp normalize_fetch_result({:error, _reason} = error), do: error
  defp normalize_fetch_result(_other), do: {:error, :invalid_token_source_response}

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(value) when is_map(value), do: Enum.into(value, [])
  defp normalize_keyword(_value), do: []

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
