defmodule Pristine.OAuth2 do
  @moduledoc """
  Generic OAuth2 control-plane helpers built on Pristine's transport boundary.
  """

  alias Pristine.Core.{Context, Request, Response}

  alias Pristine.OAuth2.{
    AuthorizationRequest,
    Backend,
    Error,
    PKCE,
    Provider,
    Token
  }

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec available?() :: boolean()
  def available?, do: Backend.available?()

  @spec authorization_request(Provider.t(), keyword()) :: result(AuthorizationRequest.t())
  def authorization_request(%Provider{} = provider, opts \\ []) do
    with :ok <- ensure_available(provider),
         {:ok, client_id} <- fetch_required(opts, :client_id, provider, :missing_client_id),
         {:ok, client} <-
           Backend.new_client(
             :authorization_code,
             authorize_client_opts(provider, opts, client_id)
           ),
         {:ok, request, params} <- build_authorization_request(provider, opts),
         {:ok, url} <- Backend.authorize_url(client, params) do
      {:ok, %AuthorizationRequest{request | url: url}}
    end
  end

  @spec authorize_url(Provider.t(), keyword()) :: result(String.t())
  def authorize_url(%Provider{} = provider, opts \\ []) do
    if Keyword.get(opts, :generate_state) || Keyword.get(opts, :pkce) do
      {:error,
       Error.new(:authorization_request_requires_explicit_values, provider: provider.name)}
    else
      with {:ok, request} <- authorization_request(provider, opts) do
        {:ok, request.url}
      end
    end
  end

  @spec exchange_code(Provider.t(), String.t(), keyword()) :: result(Token.t())
  def exchange_code(%Provider{} = provider, code, opts \\ []) when is_binary(code) do
    params =
      []
      |> Keyword.put(:code, code)
      |> maybe_put(:redirect_uri, Keyword.get(opts, :redirect_uri))
      |> maybe_put(:code_verifier, Keyword.get(opts, :pkce_verifier))
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :token_params, [])))

    token_request(provider, provider.token_url, :authorization_code, params, opts)
  end

  @spec refresh_token(Provider.t(), String.t(), keyword()) :: result(Token.t())
  def refresh_token(%Provider{} = provider, refresh_token, opts \\ [])
      when is_binary(refresh_token) do
    params =
      [refresh_token: refresh_token]
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :token_params, [])))

    token_request(provider, provider.token_url, :refresh_token, params, opts)
  end

  @spec client_credentials(Provider.t(), keyword()) :: result(Token.t())
  def client_credentials(%Provider{} = provider, opts \\ []) do
    params = normalize_keyword(Keyword.get(opts, :token_params, []))
    token_request(provider, provider.token_url, :client_credentials, params, opts)
  end

  @spec password_token(Provider.t(), String.t(), String.t(), keyword()) :: result(Token.t())
  def password_token(%Provider{} = provider, username, password, opts \\ [])
      when is_binary(username) and is_binary(password) do
    params =
      [username: username, password: password]
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :token_params, [])))

    token_request(provider, provider.token_url, :password, params, opts)
  end

  @spec revoke_token(Provider.t(), String.t(), keyword()) :: result(map())
  def revoke_token(%Provider{} = provider, token, opts \\ []) when is_binary(token) do
    control_request(provider, provider.revocation_url, %{token: token}, opts)
  end

  @spec introspect_token(Provider.t(), String.t(), keyword()) :: result(map())
  def introspect_token(%Provider{} = provider, token, opts \\ []) when is_binary(token) do
    control_request(provider, provider.introspection_url, %{token: token}, opts)
  end

  defp build_authorization_request(provider, opts) do
    state = authorization_state(opts)
    pkce = authorization_pkce(opts)
    scopes = authorization_scopes(provider, opts)

    params =
      []
      |> maybe_put(:scope, scopes)
      |> maybe_put(:state, state)
      |> maybe_put(:code_challenge, pkce[:challenge])
      |> maybe_put(:code_challenge_method, pkce_method_param(pkce[:method]))
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :params, [])))

    {:ok,
     %AuthorizationRequest{
       state: state,
       pkce_verifier: pkce[:verifier],
       pkce_challenge: pkce[:challenge],
       pkce_method: pkce[:method]
     }, params}
  end

  defp token_request(provider, nil, _strategy, _params, _opts) do
    {:error, Error.new(:missing_token_url, provider: provider.name)}
  end

  defp token_request(%Provider{} = provider, path, strategy, params, opts) do
    with :ok <- ensure_available(provider),
         {:ok, context} <- fetch_context(opts, provider),
         {:ok, client_id} <- fetch_required(opts, :client_id, provider, :missing_client_id),
         {:ok, client} <-
           Backend.new_client(strategy, token_client_opts(provider, opts, client_id)),
         {:ok, prepared_client} <-
           Backend.prepare_token_request(client, strategy, params, request_headers(opts)),
         {:ok, request} <- build_token_request(provider, path, prepared_client, context, opts),
         {:ok, %Response{} = response} <- context.transport.send(request, context),
         {:ok, body} <- decode_response_body(response, context),
         :ok <- ensure_success(response, body, provider),
         {:ok, backend_token} <- Backend.access_token(body) do
      {:ok, Token.from_backend_token(backend_token)}
    end
  end

  defp control_request(provider, nil, _params, _opts) do
    {:error, Error.new(:missing_control_url, provider: provider.name)}
  end

  defp control_request(%Provider{} = provider, path, params, opts) do
    with {:ok, context} <- fetch_context(opts, provider),
         {:ok, request} <- build_control_request(provider, path, params, context, opts),
         {:ok, %Response{} = response} <- context.transport.send(request, context),
         {:ok, body} <- decode_response_body(response, context),
         :ok <- ensure_success(response, body, provider) do
      {:ok, body}
    end
  end

  defp authorize_client_opts(provider, opts, client_id) do
    [
      authorize_url: provider.authorize_url || "",
      client_id: client_id,
      client_secret: Keyword.get(opts, :client_secret, ""),
      redirect_uri: Keyword.get(opts, :redirect_uri, ""),
      site: provider.site || "",
      token_method: provider.token_method,
      token_url: provider.token_url || ""
    ]
  end

  defp token_client_opts(provider, opts, client_id) do
    [
      authorize_url: provider.authorize_url || "",
      client_id: client_id,
      client_secret: Keyword.get(opts, :client_secret, ""),
      redirect_uri: Keyword.get(opts, :redirect_uri, ""),
      site: provider.site || "",
      token_method: provider.token_method,
      token_url: provider.token_url || ""
    ]
  end

  defp build_token_request(provider, path, prepared_client, context, opts) do
    params =
      prepared_client
      |> Map.get(:params, %{})
      |> stringify_keys()
      |> reject_blank_values()

    headers = prepared_client |> Map.get(:headers, []) |> normalize_headers()

    with {:ok, {headers, params}} <- apply_client_auth_method(provider, headers, params, opts),
         {:ok, body} <-
           encode_request_body(
             provider.token_method,
             provider.token_content_type,
             params,
             context
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
         endpoint_id: "oauth2.token",
         metadata: %{provider: provider.name}
       }}
    end
  end

  defp build_control_request(provider, path, params, context, opts) do
    params = params |> stringify_keys() |> reject_blank_values()
    headers = normalize_headers(request_headers(opts))

    with {:ok, {headers, params}} <- apply_client_auth_method(provider, headers, params, opts),
         {:ok, body} <-
           encode_request_body(
             provider.token_method,
             provider.token_content_type,
             params,
             context
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
         endpoint_id: "oauth2.control",
         metadata: %{provider: provider.name}
       }}
    end
  end

  defp request_url(site, path, :get, params) do
    {:ok, append_query(build_url(site, path), params)}
  end

  defp request_url(site, path, _method, _params), do: {:ok, build_url(site, path)}

  defp encode_request_body(:get, _content_type, _params, _context), do: {:ok, nil}

  defp encode_request_body(_method, content_type, _params, _context) when is_nil(content_type),
    do: {:ok, nil}

  defp encode_request_body(_method, _content_type, params, _context) when params == %{},
    do: {:ok, nil}

  defp encode_request_body(_method, "application/json", params, %Context{serializer: serializer}) do
    serializer = serializer || Pristine.Adapters.Serializer.JSON

    case serializer.encode(params, []) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, Error.new(:request_encoding_failed, body: reason)}
    end
  end

  defp encode_request_body(
         _method,
         "application/x-www-form-urlencoded",
         params,
         _context
       ) do
    {:ok, URI.encode_query(params)}
  end

  defp encode_request_body(_method, _content_type, params, _context) do
    {:ok, params}
  end

  defp decode_response_body(%Response{body: nil}, _context), do: {:ok, %{}}
  defp decode_response_body(%Response{body: ""}, _context), do: {:ok, %{}}

  defp decode_response_body(%Response{body: body}, _context) when is_map(body),
    do: {:ok, stringify_keys(body)}

  defp decode_response_body(%Response{body: body, headers: headers}, %Context{
         serializer: serializer
       }) do
    serializer = serializer || Pristine.Adapters.Serializer.JSON
    content_type = response_content_type(headers)

    cond do
      String.contains?(content_type, "application/x-www-form-urlencoded") ->
        {:ok, URI.decode_query(body)}

      String.contains?(content_type, "application/json") ->
        serializer.decode(body, nil, [])

      true ->
        case serializer.decode(body, nil, []) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _reason} -> {:ok, %{"body" => body}}
        end
    end
  end

  defp ensure_success(%Response{status: status}, _body, _provider) when status in 200..299,
    do: :ok

  defp ensure_success(%Response{} = response, body, provider) do
    {:error,
     Error.new(
       :token_request_failed,
       status: response.status,
       body: body,
       headers: normalize_header_map(response.headers),
       provider: provider.name
     )}
  end

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

  defp authorization_state(opts) do
    cond do
      is_binary(Keyword.get(opts, :state)) -> Keyword.get(opts, :state)
      Keyword.get(opts, :generate_state) -> PKCE.generate(24)
      true -> nil
    end
  end

  defp authorization_pkce(opts) do
    cond do
      is_binary(Keyword.get(opts, :pkce_challenge)) ->
        %{
          verifier: Keyword.get(opts, :pkce_verifier),
          challenge: Keyword.get(opts, :pkce_challenge),
          method: Keyword.get(opts, :pkce_method, :s256)
        }

      is_binary(Keyword.get(opts, :pkce_verifier)) ->
        verifier = Keyword.get(opts, :pkce_verifier)
        method = Keyword.get(opts, :pkce_method, :s256)
        %{verifier: verifier, challenge: PKCE.challenge(verifier, method), method: method}

      Keyword.get(opts, :pkce) ->
        verifier = PKCE.generate(32)
        method = Keyword.get(opts, :pkce_method, :s256)
        %{verifier: verifier, challenge: PKCE.challenge(verifier, method), method: method}

      true ->
        %{verifier: nil, challenge: nil, method: nil}
    end
  end

  defp authorization_scopes(provider, opts) do
    scopes =
      case Keyword.get(opts, :scopes) do
        nil -> provider.default_scopes
        list when is_list(list) -> Enum.map(list, &to_string/1)
        value when is_binary(value) -> [value]
      end

    case scopes do
      [] -> nil
      _ -> Enum.join(scopes, " ")
    end
  end

  defp fetch_context(opts, provider) do
    case Keyword.get(opts, :context) do
      %Context{transport: transport} = context when not is_nil(transport) ->
        {:ok, context}

      _other ->
        {:error, Error.new(:invalid_context, provider: provider.name)}
    end
  end

  defp fetch_required(opts, key, provider, reason) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, Error.new(reason, provider: provider.name)}
    end
  end

  defp present(value, _provider, _reason) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_value, provider, reason), do: {:error, Error.new(reason, provider: provider.name)}

  defp request_headers(opts) do
    opts
    |> Keyword.get(:headers, [])
    |> normalize_headers()
    |> Enum.into([])
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
  end

  defp normalize_headers(_headers), do: %{}

  defp normalize_header_map(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_header_map(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_header_map(_headers), do: %{}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(other), do: other

  defp response_content_type(headers) do
    headers = normalize_headers(headers)
    Map.get(headers, "content-type", "")
  end

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

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp maybe_put_header(headers, _key, nil), do: headers

  defp maybe_put_header(headers, key, value) do
    Map.put_new(headers, key, value)
  end

  defp normalize_keyword(map) when is_map(map), do: Enum.into(map, [])
  defp normalize_keyword(list) when is_list(list), do: list
  defp normalize_keyword(_other), do: []

  defp reject_blank_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp reject_blank_values(other), do: other

  defp pkce_method_param(nil), do: nil
  defp pkce_method_param(method), do: method |> to_string() |> String.upcase()

  defp ensure_available(provider) do
    if available?() do
      :ok
    else
      {:error, Error.new(:oauth2_unavailable, provider: provider.name)}
    end
  end
end
