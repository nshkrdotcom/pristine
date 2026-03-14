defmodule Pristine.Adapters.OAuthBackend.Native do
  @moduledoc """
  In-tree OAuth backend adapter for Pristine's control-plane helpers.
  """

  @behaviour Pristine.Ports.OAuthBackend

  alias Pristine.Adapters.Serializer.JSON, as: JSONSerializer
  alias Pristine.Core.Context
  alias Pristine.OAuth2.{Error, Provider, Token}
  alias Pristine.Ports.OAuthBackend.Request

  @impl true
  def available?, do: true

  @impl true
  def authorization_url(%Provider{} = provider, opts) when is_list(opts) do
    with :ok <- ensure_authorize_url(provider),
         {:ok, client_id} <- present(Keyword.get(opts, :client_id), provider, :missing_client_id) do
      params =
        opts
        |> Keyword.get(:params, [])
        |> normalize_params()
        |> Map.put_new("response_type", "code")
        |> Map.put("client_id", client_id)
        |> maybe_put("redirect_uri", Keyword.get(opts, :redirect_uri))
        |> reject_blank_values()

      {:ok, append_query(build_url(provider.site, provider.authorize_url), params)}
    end
  end

  @impl true
  def build_request(%Provider{} = provider, {:token, grant_type}, params, opts)
      when is_list(opts) do
    with :ok <- ensure_token_url(provider),
         request_params <- token_request_params(grant_type, params),
         {:ok, request} <- oauth_request(provider, provider.token_url, request_params, opts) do
      {:ok, %{request | id: "oauth2.token"}}
    end
  end

  def build_request(%Provider{} = provider, :revoke, params, opts) when is_list(opts) do
    with :ok <- ensure_revocation_url(provider),
         {:ok, request} <- oauth_request(provider, provider.revocation_url, params, opts) do
      {:ok, %{request | id: "oauth2.control"}}
    end
  end

  def build_request(%Provider{} = provider, :introspect, params, opts) when is_list(opts) do
    with :ok <- ensure_introspection_url(provider),
         {:ok, request} <- oauth_request(provider, provider.introspection_url, params, opts) do
      {:ok, %{request | id: "oauth2.control"}}
    end
  end

  @impl true
  def normalize_token_response(_provider, body) when is_map(body) do
    {:ok, Token.from_backend_token(body)}
  end

  def normalize_token_response(provider, body) do
    {:error,
     Error.new(
       :token_request_failed,
       body: body,
       provider: provider.name,
       message: "oauth backend could not normalize the token response"
     )}
  end

  defp oauth_request(provider, path, params, opts) do
    params = params |> normalize_params() |> reject_blank_values()
    headers = opts |> Keyword.get(:headers, []) |> normalize_headers()

    with {:ok, {headers, params}} <- apply_client_auth_method(provider, headers, params, opts),
         {:ok, body} <-
           encode_request_body(
             provider.token_method,
             provider.token_content_type,
             params,
             Keyword.get(opts, :context)
           ),
         {:ok, url} <- request_url(provider.site, path, provider.token_method, params) do
      {:ok,
       %Request{
         method: provider.token_method,
         url: url,
         headers:
           headers
           |> maybe_put_header("accept", "application/json")
           |> maybe_put_header(
             "content-type",
             body_content_type(provider.token_method, provider.token_content_type)
           ),
         body: body,
         metadata: %{provider: provider.name}
       }}
    end
  end

  defp token_request_params(grant_type, params) do
    params
    |> normalize_params()
    |> Map.put_new("grant_type", grant_type_param(grant_type))
  end

  defp grant_type_param(:authorization_code), do: "authorization_code"
  defp grant_type_param(:refresh_token), do: "refresh_token"
  defp grant_type_param(:client_credentials), do: "client_credentials"
  defp grant_type_param(:password), do: "password"

  defp encode_request_body(:get, _content_type, _params, _context), do: {:ok, nil}
  defp encode_request_body(_method, nil, _params, _context), do: {:ok, nil}

  defp encode_request_body(_method, _content_type, params, _context) when params == %{},
    do: {:ok, nil}

  defp encode_request_body(_method, "application/json", params, %Context{serializer: serializer}) do
    serializer = serializer || Pristine.Adapters.Serializer.JSON

    case serializer.encode(params, []) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, Error.new(:request_encoding_failed, body: reason)}
    end
  end

  defp encode_request_body(_method, "application/json", params, _context) do
    case JSONSerializer.encode(params, []) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, Error.new(:request_encoding_failed, body: reason)}
    end
  end

  defp encode_request_body(_method, "application/x-www-form-urlencoded", params, _context) do
    {:ok, URI.encode_query(params)}
  end

  defp encode_request_body(_method, _content_type, params, _context), do: {:ok, params}

  defp request_url(site, path, :get, params) do
    {:ok, append_query(build_url(site, path), params)}
  end

  defp request_url(site, path, _method, _params), do: {:ok, build_url(site, path)}

  defp apply_client_auth_method(provider, headers, params, opts) do
    client_id = Keyword.get(opts, :client_id)
    client_secret = Keyword.get(opts, :client_secret)

    case provider.client_auth_method do
      :basic ->
        with {:ok, client_id} <- present(client_id, provider, :missing_client_id),
             {:ok, client_secret} <- present(client_secret, provider, :missing_client_secret) do
          auth = Base.encode64("#{client_id}:#{client_secret}")

          {:ok,
           {headers
            |> Map.delete("authorization")
            |> Map.put("authorization", "Basic #{auth}"),
            Map.drop(params, ["client_id", "client_secret"])}}
        end

      :request_body ->
        with {:ok, client_id} <- present(client_id, provider, :missing_client_id),
             {:ok, client_secret} <- present(client_secret, provider, :missing_client_secret) do
          {:ok,
           {Map.delete(headers, "authorization"),
            params
            |> Map.put("client_id", client_id)
            |> Map.put("client_secret", client_secret)}}
        end

      :none ->
        with {:ok, client_id} <- present(client_id, provider, :missing_client_id) do
          {:ok,
           {Map.delete(headers, "authorization"),
            params
            |> Map.delete("client_secret")
            |> Map.put("client_id", client_id)}}
        end
    end
  end

  defp ensure_authorize_url(%Provider{authorize_url: nil} = provider) do
    {:error, Error.new(:missing_authorize_url, provider: provider.name)}
  end

  defp ensure_authorize_url(_provider), do: :ok

  defp ensure_token_url(%Provider{token_url: nil} = provider) do
    {:error, Error.new(:missing_token_url, provider: provider.name)}
  end

  defp ensure_token_url(_provider), do: :ok

  defp ensure_revocation_url(%Provider{revocation_url: nil} = provider) do
    {:error, Error.new(:missing_revocation_url, provider: provider.name)}
  end

  defp ensure_revocation_url(_provider), do: :ok

  defp ensure_introspection_url(%Provider{introspection_url: nil} = provider) do
    {:error, Error.new(:missing_introspection_url, provider: provider.name)}
  end

  defp ensure_introspection_url(_provider), do: :ok

  defp present(value, _provider, _reason) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_value, provider, reason), do: {:error, Error.new(reason, provider: provider.name)}

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_params(params) when is_list(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_params(_params), do: %{}

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
  end

  defp normalize_headers(_headers), do: %{}

  defp reject_blank_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_header(headers, _key, nil), do: headers
  defp maybe_put_header(headers, key, value), do: Map.put_new(headers, key, value)

  defp append_query(url, params) when params == %{}, do: url
  defp append_query(url, params), do: url <> "?" <> URI.encode_query(params)

  defp build_url(site, path) when is_binary(path) do
    if String.starts_with?(path, "http://") or String.starts_with?(path, "https://") do
      path
    else
      to_string(site || "") <> path
    end
  end

  defp build_url(site, nil), do: to_string(site || "")
  defp build_url(site, path), do: to_string(site || "") <> to_string(path)

  defp body_content_type(:get, _content_type), do: nil
  defp body_content_type(_method, content_type), do: content_type
end
