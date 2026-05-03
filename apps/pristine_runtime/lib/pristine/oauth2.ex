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

  alias Pristine.Ports.OAuthBackend.Request, as: BackendRequest

  @oauth_body_atom_keys %{
    "error" => :error,
    "error_description" => :error_description
  }

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec available?() :: boolean()
  def available?, do: Backend.available?()

  @spec authorization_request(Provider.t(), keyword()) :: result(AuthorizationRequest.t())
  def authorization_request(%Provider{} = provider, opts \\ []) do
    with :ok <- ensure_available(provider),
         {:ok, client_id} <- fetch_required(opts, :client_id, provider, :missing_client_id),
         {:ok, %AuthorizationRequest{} = request, params} <-
           build_authorization_request(provider, opts),
         {:ok, url} <-
           Backend.authorization_url(
             provider,
             authorization_backend_opts(opts, client_id, params)
           ) do
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

    token_request(provider, :authorization_code, params, opts)
  end

  @spec refresh_token(Provider.t(), String.t(), keyword()) :: result(Token.t())
  def refresh_token(%Provider{} = provider, refresh_token, opts \\ [])
      when is_binary(refresh_token) do
    params =
      [refresh_token: refresh_token]
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :token_params, [])))

    token_request(provider, :refresh_token, params, opts)
  end

  @spec client_credentials(Provider.t(), keyword()) :: result(Token.t())
  def client_credentials(%Provider{} = provider, opts \\ []) do
    params = normalize_keyword(Keyword.get(opts, :token_params, []))
    token_request(provider, :client_credentials, params, opts)
  end

  @spec password_token(Provider.t(), String.t(), String.t(), keyword()) :: result(Token.t())
  def password_token(%Provider{} = provider, username, password, opts \\ [])
      when is_binary(username) and is_binary(password) do
    params =
      [username: username, password: password]
      |> Keyword.merge(normalize_keyword(Keyword.get(opts, :token_params, [])))

    token_request(provider, :password, params, opts)
  end

  @spec revoke_token(Provider.t(), String.t(), keyword()) :: result(map())
  def revoke_token(%Provider{} = provider, token, opts \\ []) when is_binary(token) do
    control_request(provider, :revoke, %{token: token}, opts)
  end

  @spec introspect_token(Provider.t(), String.t(), keyword()) :: result(map())
  def introspect_token(%Provider{} = provider, token, opts \\ []) when is_binary(token) do
    control_request(provider, :introspect, %{token: token}, opts)
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

  defp token_request(%Provider{} = provider, _grant_type, _params, _opts)
       when is_nil(provider.token_url) do
    {:error, Error.new(:missing_token_url, provider: provider.name)}
  end

  defp token_request(%Provider{} = provider, grant_type, params, opts) do
    with :ok <- ensure_available(provider),
         {:ok, context} <- fetch_context(opts, provider),
         {:ok, client_id} <- fetch_required(opts, :client_id, provider, :missing_client_id),
         {:ok, backend_request} <-
           Backend.build_request(
             provider,
             {:token, grant_type},
             params,
             backend_request_opts(opts, context, client_id)
           ),
         {:ok, request} <- to_transport_request(backend_request),
         {:ok, %Response{} = response} <- context.transport.send(request, context),
         {:ok, body} <- decode_response_body(response, context),
         :ok <- ensure_success(response, body, provider) do
      Backend.normalize_token_response(provider, body)
    end
  end

  defp control_request(%Provider{} = provider, :revoke, _params, _opts)
       when is_nil(provider.revocation_url) do
    {:error, Error.new(:missing_revocation_url, provider: provider.name)}
  end

  defp control_request(%Provider{} = provider, :introspect, _params, _opts)
       when is_nil(provider.introspection_url) do
    {:error, Error.new(:missing_introspection_url, provider: provider.name)}
  end

  defp control_request(%Provider{} = provider, kind, params, opts) do
    with :ok <- ensure_available(provider),
         {:ok, context} <- fetch_context(opts, provider),
         {:ok, client_id} <- fetch_required(opts, :client_id, provider, :missing_client_id),
         {:ok, backend_request} <-
           Backend.build_request(
             provider,
             kind,
             params,
             backend_request_opts(opts, context, client_id)
           ),
         {:ok, request} <- to_transport_request(backend_request),
         {:ok, %Response{} = response} <- context.transport.send(request, context),
         {:ok, body} <- decode_response_body(response, context),
         :ok <- ensure_success(response, body, provider) do
      {:ok, body}
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

  defp authorization_backend_opts(opts, client_id, params) do
    []
    |> Keyword.put(:client_id, client_id)
    |> maybe_put(:redirect_uri, Keyword.get(opts, :redirect_uri))
    |> Keyword.put(:params, params)
  end

  defp backend_request_opts(opts, context, client_id) do
    []
    |> Keyword.put(:context, context)
    |> Keyword.put(:client_id, client_id)
    |> maybe_put(:client_secret, Keyword.get(opts, :client_secret))
    |> maybe_put(:redirect_uri, Keyword.get(opts, :redirect_uri))
    |> maybe_put(:headers, Keyword.get(opts, :headers))
  end

  defp to_transport_request(%BackendRequest{} = request) do
    {:ok,
     %Request{
       method: request.method,
       url: request.url,
       headers: request.headers,
       body: request.body,
       endpoint_id: request.id,
       metadata: request.metadata
     }}
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

  defp ensure_success(%Response{status: status} = response, body, provider)
       when status in 200..299 do
    case oauth_error_body(body) do
      nil ->
        :ok

      error_body ->
        {:error,
         Error.new(
           :token_request_failed,
           status: response.status,
           body: body,
           headers: normalize_header_map(response.headers),
           provider: provider.name,
           message: oauth_error_message(error_body)
         )}
    end
  end

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

  defp oauth_error_body(body) when is_map(body) do
    case body_value(body, "error") do
      value when is_binary(value) and value != "" -> body
      _other -> nil
    end
  end

  defp oauth_error_body(_body), do: nil

  defp oauth_error_message(body) when is_map(body) do
    error = body_value(body, "error")
    description = body_value(body, "error_description")

    cond do
      is_binary(error) and error != "" and is_binary(description) and description != "" ->
        "oauth provider returned an error: #{error} - #{description}"

      is_binary(error) and error != "" ->
        "oauth provider returned an error: #{error}"

      true ->
        "oauth provider returned an error"
    end
  end

  defp body_value(body, key) when is_map(body) do
    Map.get(body, key) || Map.get(body, Map.get(@oauth_body_atom_keys, key))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp response_content_type(headers) do
    headers = normalize_headers(headers)
    Map.get(headers, "content-type", "")
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, _key, []), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp normalize_keyword(map) when is_map(map), do: Enum.into(map, [])
  defp normalize_keyword(list) when is_list(list), do: list
  defp normalize_keyword(_other), do: []

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
