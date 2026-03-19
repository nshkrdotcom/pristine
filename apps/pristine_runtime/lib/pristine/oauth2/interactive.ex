defmodule Pristine.OAuth2.Interactive do
  @moduledoc """
  Interactive authorization-code orchestration for OAuth2 providers.
  """

  alias Pristine.Adapters.OAuthBrowser.SystemCmd, as: SystemBrowser
  alias Pristine.Adapters.OAuthCallbackListener.Bandit, as: BanditCallbackListener
  alias Pristine.OAuth2
  alias Pristine.OAuth2.{Error, Provider}

  @default_timeout_ms 120_000

  @type io_device :: pid() | atom()

  @spec authorize(Provider.t(), keyword()) ::
          {:ok, OAuth2.Token.t()} | {:error, Error.t() | term()}
  def authorize(%Provider{} = provider, opts \\ []) when is_list(opts) do
    with {:ok, redirect_uri} <- fetch_redirect_uri(provider, opts),
         {:ok, request} <-
           OAuth2.authorization_request(provider, authorization_request_opts(opts)) do
      callback_server = callback_server(opts)
      {server, note} = maybe_start_callback_server(redirect_uri, callback_server, opts)

      result =
        with :ok <- print_authorization_url(request.url, note, output(opts)),
             :ok <- maybe_open_browser(request.url, opts),
             {:ok, callback} <-
               authorization_callback(
                 provider,
                 request,
                 redirect_uri,
                 callback_server,
                 server,
                 input(opts),
                 output(opts),
                 opts
               ),
             {:ok, code} <- extract_code(provider, callback, request.state, redirect_uri) do
          OAuth2.exchange_code(provider, code, exchange_opts(opts, request))
        end

      maybe_stop(callback_server, server)
      result
    end
  end

  defp authorization_request_opts(opts) do
    if manual_only_flow?(opts) do
      opts
    else
      Keyword.put_new(opts, :generate_state, true)
    end
  end

  defp authorization_callback(
         provider,
         request,
         redirect_uri,
         callback_server,
         server,
         input,
         output,
         opts
       ) do
    if server do
      case callback_server.await(server, timeout_ms(opts)) do
        {:ok, _callback} = success ->
          success

        {:error, %Error{reason: :authorization_callback_timeout}} ->
          write_line(output, "Callback capture timed out. Falling back to manual paste-back.")
          manual_callback(provider, request, redirect_uri, input, output)

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          write_line(
            output,
            "Callback capture failed (#{inspect(reason)}). Falling back to manual paste-back."
          )

          manual_callback(provider, request, redirect_uri, input, output)
      end
    else
      manual_callback(provider, request, redirect_uri, input, output)
    end
  end

  defp manual_callback(_provider, request, redirect_uri, input, output) do
    write_manual_prompt(output, request.state)
    prompt(output, "> ")

    case IO.gets(input, "") do
      data when is_binary(data) ->
        parse_manual_entry(String.trim(data), redirect_uri)

      _other ->
        {:error, Error.new(:manual_input_cancelled)}
    end
  end

  defp extract_code(_provider, %{code: code, state: state}, expected_state, _redirect_uri) do
    validate_state(code, state, expected_state)
  end

  defp extract_code(_provider, %{"code" => code, "state" => state}, expected_state, _redirect_uri) do
    validate_state(code, state, expected_state)
  end

  defp maybe_start_callback_server(redirect_uri, callback_server, opts) do
    cond do
      Keyword.get(opts, :manual?, false) ->
        {nil, nil}

      Keyword.get(opts, :allow_loopback?, true) == false ->
        {nil, nil}

      true ->
        maybe_start_loopback_callback_server(redirect_uri, callback_server)
    end
  end

  defp maybe_start_loopback_callback_server(redirect_uri, callback_server) do
    if loopback_redirect_uri?(callback_server, redirect_uri) do
      case callback_server.start(redirect_uri, receiver: self()) do
        {:ok, server} ->
          {server, "Waiting for the OAuth callback on #{redirect_uri}"}

        {:error, %Error{} = error} ->
          {nil,
           "Callback capture unavailable (#{error.message}). Falling back to manual paste-back."}

        {:error, reason} ->
          {nil,
           "Callback capture unavailable (#{inspect(reason)}). Falling back to manual paste-back."}
      end
    else
      {nil,
       "Loopback callback capture is only available for literal loopback http redirect URIs. Falling back to manual paste-back."}
    end
  end

  defp print_authorization_url(url, note, output) do
    write_line(output, "Open this URL to authorize:")
    write_line(output, url)

    if is_binary(note) do
      write_line(output, note)
    end

    :ok
  end

  defp maybe_open_browser(url, opts) do
    if Keyword.get(opts, :open_browser?, true) do
      case browser(opts).open(url, opts) do
        :ok ->
          :ok

        {:error, reason} ->
          write_line(output(opts), "Browser open failed: #{format_reason(reason)}")
      end
    else
      :ok
    end
  end

  defp parse_manual_entry("", _redirect_uri), do: {:error, Error.new(:manual_input_cancelled)}

  defp parse_manual_entry(entry, redirect_uri) do
    uri = URI.parse(entry)

    if is_binary(uri.scheme) and is_binary(uri.host) do
      with :ok <- ensure_redirect_match(uri, redirect_uri),
           params <- manual_callback_params(uri),
           :ok <- ensure_no_callback_error(params),
           {:ok, code} <- fetch_code(params) do
        {:ok, %{code: code, state: blank_to_nil(params["state"])}}
      end
    else
      {:ok, %{code: entry, state: nil}}
    end
  end

  defp ensure_redirect_match(callback_uri, redirect_uri) do
    with {:ok, configured} <- normalized_uri(redirect_uri),
         {:ok, callback} <- normalized_uri(URI.to_string(callback_uri)) do
      if uri_match?(configured, callback) do
        :ok
      else
        {:error, Error.new(:redirect_uri_mismatch)}
      end
    end
  end

  defp normalized_uri(uri_string) do
    case URI.parse(uri_string) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        {:ok,
         %{
           scheme: scheme,
           host: host,
           port: effective_port(uri),
           path: normalized_path(uri.path)
         }}

      _other ->
        {:error, Error.new(:invalid_redirect_uri)}
    end
  end

  defp uri_match?(left, right) do
    left.scheme == right.scheme and left.host == right.host and left.port == right.port and
      left.path == right.path
  end

  defp manual_callback_params(%URI{} = uri) do
    query_params = uri.query |> blank_to_nil() |> decode_query()
    fragment_params = uri.fragment |> blank_to_nil() |> decode_query()
    Map.merge(query_params, fragment_params)
  end

  defp ensure_no_callback_error(%{"error" => error} = params)
       when is_binary(error) and error != "" do
    {:error,
     Error.new(
       :authorization_callback_error,
       body: params,
       message: callback_error_message(error, params["error_description"])
     )}
  end

  defp ensure_no_callback_error(_params), do: :ok

  defp fetch_code(%{"code" => code}) when is_binary(code) and code != "", do: {:ok, code}
  defp fetch_code(_params), do: {:error, Error.new(:authorization_code_missing)}

  defp validate_state(code, _state, nil), do: {:ok, code}

  defp validate_state(code, state, expected_state) do
    if blank_to_nil(state) == expected_state do
      {:ok, code}
    else
      {:error, Error.new(:authorization_state_mismatch)}
    end
  end

  defp exchange_opts(opts, request) do
    []
    |> maybe_put(:client_id, Keyword.get(opts, :client_id))
    |> maybe_put(:client_secret, Keyword.get(opts, :client_secret))
    |> maybe_put(:context, Keyword.get(opts, :context))
    |> maybe_put(:headers, Keyword.get(opts, :headers))
    |> maybe_put(:pkce_verifier, request.pkce_verifier)
    |> maybe_put(:redirect_uri, Keyword.get(opts, :redirect_uri))
    |> maybe_put(:token_params, Keyword.get(opts, :token_params))
  end

  defp fetch_redirect_uri(provider, opts) do
    case Keyword.get(opts, :redirect_uri) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _other ->
        {:error, Error.new(:missing_redirect_uri, provider: provider.name)}
    end
  end

  defp callback_server(opts), do: Keyword.get(opts, :callback_server, BanditCallbackListener)
  defp browser(opts), do: Keyword.get(opts, :browser, SystemBrowser)
  defp timeout_ms(opts), do: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
  defp input(opts), do: Keyword.get(opts, :input, :stdio)
  defp output(opts), do: Keyword.get(opts, :output, :stdio)
  defp manual_only_flow?(opts), do: Keyword.get(opts, :manual?, false)

  defp maybe_stop(_callback_server, nil), do: :ok
  defp maybe_stop(callback_server, server), do: callback_server.stop(server)

  defp prompt(output, text), do: IO.write(output, text)
  defp write_line(output, text), do: IO.puts(output, text)

  defp write_manual_prompt(output, nil) do
    write_line(output, "Paste the full redirect URL or the raw authorization code.")
  end

  defp write_manual_prompt(output, _expected_state) do
    write_line(output, "Paste the full redirect URL.")
  end

  defp decode_query(nil), do: %{}
  defp decode_query(value), do: URI.decode_query(value)

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: "https"}), do: 443
  defp effective_port(%URI{}), do: 80

  defp normalized_path(nil), do: "/"
  defp normalized_path(""), do: "/"
  defp normalized_path(path), do: path

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp callback_error_message(error, nil),
    do: "authorization callback returned error #{inspect(error)}"

  defp callback_error_message(error, description) do
    "authorization callback returned error #{inspect(error)}: #{description}"
  end

  defp loopback_redirect_uri?(callback_server, redirect_uri) do
    if function_exported?(callback_server, :loopback_redirect_uri?, 1) do
      callback_server.loopback_redirect_uri?(redirect_uri)
    else
      BanditCallbackListener.loopback_redirect_uri?(redirect_uri)
    end
  end

  defp format_reason({:command_failed, command, status, output}) do
    "#{command} exited with status #{status}: #{String.trim(output)}"
  end

  defp format_reason({:command_unavailable, command, reason}) do
    "#{command} is unavailable (#{inspect(reason)})"
  end

  defp format_reason({:unsupported_os, os_type}), do: "unsupported OS #{inspect(os_type)}"
  defp format_reason(reason), do: inspect(reason)
end
