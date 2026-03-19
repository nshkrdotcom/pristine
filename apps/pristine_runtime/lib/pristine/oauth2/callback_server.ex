defmodule Pristine.OAuth2.CallbackServer do
  @moduledoc """
  Exact loopback callback capture for interactive OAuth flows.
  """

  use GenServer

  alias Pristine.OAuth2.Error

  @compile {:no_warn_undefined, [Bandit, Plug.Conn]}

  @callback_message :pristine_oauth2_callback

  defstruct [:pid, :redirect_uri]

  @type t :: %__MODULE__{
          pid: pid(),
          redirect_uri: String.t()
        }

  @type callback_result ::
          {:ok, %{code: String.t(), request_uri: String.t(), state: String.t() | nil}}
          | {:error, Error.t()}

  @type redirect_target :: %{
          redirect_uri: String.t(),
          host: String.t(),
          ip: :inet.ip_address(),
          path: String.t(),
          port: pos_integer(),
          scheme: String.t()
        }

  @spec start(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def start(redirect_uri, opts \\ []) when is_binary(redirect_uri) and is_list(opts) do
    with {:ok, redirect} <- parse_loopback_redirect_uri(redirect_uri),
         {:ok, pid} <- start_server(redirect, opts) do
      {:ok, %__MODULE__{pid: pid, redirect_uri: redirect.redirect_uri}}
    end
  end

  @spec await(t(), timeout()) :: callback_result()
  def await(%__MODULE__{pid: pid} = server, timeout_ms) when is_integer(timeout_ms) do
    receive do
      {@callback_message, ^pid, result} ->
        stop(server)
        result
    after
      timeout_ms ->
        stop(server)
        {:error, Error.new(:authorization_callback_timeout)}
    end
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  @spec loopback_redirect_uri?(String.t()) :: boolean()
  def loopback_redirect_uri?(redirect_uri) when is_binary(redirect_uri) do
    match?({:ok, _redirect}, parse_loopback_redirect_uri(redirect_uri))
  end

  @doc false
  @spec handle_http_request(pid(), map(), redirect_target()) ::
          {map(), non_neg_integer(), iodata()}
  def handle_http_request(server, conn, redirect) do
    cond do
      conn.method != "GET" ->
        {conn, 405, failure_page("Method not allowed")}

      not request_matches_redirect?(conn, redirect) ->
        {conn, 404, failure_page("Not found")}

      true ->
        conn = Plug.Conn.fetch_query_params(conn)
        callback_uri = callback_uri(redirect, conn.query_string)

        response =
          GenServer.call(server, {:report_callback, conn.params, callback_uri}, :infinity)

        {conn, response.status, response.body}
    end
  end

  @impl GenServer
  def init(%{bandit_module: bandit_module, receiver: receiver, redirect: redirect}) do
    plug_opts = [server: self(), redirect: redirect]

    bandit_opts = [
      plug: {__MODULE__.CallbackPlug, plug_opts},
      ip: redirect.ip,
      port: redirect.port,
      startup_log: false,
      thousand_island_options: [num_acceptors: 1, silent_terminate_on_error: true]
    ]

    case bandit_module.start_link(bandit_opts) do
      {:ok, bandit_pid} ->
        {:ok,
         %{bandit_pid: bandit_pid, delivered?: false, receiver: receiver, redirect: redirect}}

      {:error, reason} ->
        {:stop,
         {:error,
          Error.new(
            :loopback_callback_unavailable,
            message: "failed to start callback server: #{inspect(reason)}"
          )}}
    end
  end

  @impl GenServer
  def handle_call({:report_callback, params, callback_uri}, _from, state) do
    {reply, state} =
      if state.delivered? do
        {%{body: failure_page("Authorization callback already handled"), status: 409}, state}
      else
        result = callback_result(params, callback_uri)
        send(state.receiver, {@callback_message, self(), result})
        Process.send_after(self(), :shutdown_listener, 0)
        {response_for_result(result), %{state | delivered?: true}}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info(:shutdown_listener, %{bandit_pid: bandit_pid} = state) do
    shutdown_bandit(bandit_pid)
    {:noreply, %{state | bandit_pid: nil}}
  end

  @impl GenServer
  def terminate(_reason, %{bandit_pid: bandit_pid}) when is_pid(bandit_pid) do
    shutdown_bandit(bandit_pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_server(redirect, opts) do
    receiver = Keyword.get(opts, :receiver, self())
    bandit_module = Keyword.get(opts, :bandit_module, Bandit)

    if dependencies_available?(opts, bandit_module) do
      case GenServer.start_link(__MODULE__, %{
             bandit_module: bandit_module,
             receiver: receiver,
             redirect: redirect
           }) do
        {:ok, pid} -> {:ok, pid}
        {:error, %Error{} = error} -> {:error, error}
        {:error, {:error, %Error{} = error}} -> {:error, error}
        {:error, reason} -> {:error, Error.new(:loopback_callback_unavailable, body: reason)}
      end
    else
      {:error,
       Error.new(
         :loopback_callback_unavailable,
         message:
           "loopback callback capture requires optional :plug and :bandit dependencies to be installed"
       )}
    end
  end

  defp dependencies_available?(opts, bandit_module) do
    Keyword.get_lazy(opts, :dependencies_available?, fn ->
      Code.ensure_loaded?(Plug.Conn) and Code.ensure_loaded?(bandit_module) and
        function_exported?(bandit_module, :start_link, 1)
    end)
  end

  defp parse_loopback_redirect_uri(redirect_uri) do
    case URI.parse(redirect_uri) do
      %URI{
        scheme: "http",
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil
      }
      when is_binary(host) and is_integer(port) and port > 0 ->
        with {:ok, ip} <- parse_loopback_ip(host) do
          {:ok,
           %{
             redirect_uri:
               normalize_redirect_uri_string("http", host, port, normalize_path(path)),
             scheme: "http",
             host: host,
             ip: ip,
             port: port,
             path: normalize_path(path)
           }}
        end

      %URI{scheme: scheme} when scheme not in [nil, "", "http"] ->
        {:error, Error.new(:unsupported_callback_scheme)}

      _other ->
        {:error, Error.new(:invalid_redirect_uri)}
    end
  end

  defp parse_loopback_ip("localhost") do
    {:error,
     Error.new(
       :loopback_callback_unavailable,
       message:
         "loopback callback capture requires a literal loopback IP host such as 127.0.0.1 or ::1"
     )}
  end

  defp parse_loopback_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _} = ip} ->
        {:ok, ip}

      {:ok, {0, 0, 0, 0, 0, 0, 0, 1} = ip} ->
        {:ok, ip}

      {:ok, _ip} ->
        {:error, Error.new(:loopback_callback_unavailable)}

      {:error, _reason} ->
        {:error, Error.new(:invalid_redirect_uri)}
    end
  end

  defp request_matches_redirect?(conn, redirect) do
    conn.port == redirect.port and conn.request_path == redirect.path and
      host_matches?(conn.host, redirect.ip)
  end

  defp host_matches?(host, expected_ip) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ^expected_ip} -> true
      _other -> false
    end
  end

  defp host_matches?(_host, _expected_ip), do: false

  defp callback_result(params, callback_uri) do
    cond do
      present?(params["error"]) ->
        {:error,
         Error.new(
           :authorization_callback_error,
           body: %{
             "error" => params["error"],
             "error_description" => params["error_description"],
             "request_uri" => callback_uri
           },
           message: callback_error_message(params["error"], params["error_description"])
         )}

      present?(params["code"]) ->
        {:ok,
         %{code: params["code"], request_uri: callback_uri, state: blank_to_nil(params["state"])}}

      true ->
        {:error, Error.new(:authorization_code_missing, body: %{"request_uri" => callback_uri})}
    end
  end

  defp response_for_result({:ok, _callback}) do
    %{body: success_page("Authorization received. Return to the terminal."), status: 200}
  end

  defp response_for_result({:error, %Error{} = error}) do
    %{body: failure_page(error.message), status: 400}
  end

  defp callback_error_message(error, nil),
    do: "authorization callback returned error #{inspect(error)}"

  defp callback_error_message(error, description) do
    "authorization callback returned error #{inspect(error)}: #{description}"
  end

  defp callback_uri(redirect, ""), do: redirect.redirect_uri
  defp callback_uri(redirect, query_string), do: redirect.redirect_uri <> "?" <> query_string

  defp normalize_redirect_uri_string(scheme, host, port, path) do
    scheme <> "://" <> host <> ":" <> Integer.to_string(port) <> path
  end

  defp normalize_path(nil), do: "/"
  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: path

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp success_page(message) do
    """
    <html>
      <body>
        <h1>OAuth complete</h1>
        <p>#{message}</p>
      </body>
    </html>
    """
  end

  defp failure_page(message) do
    """
    <html>
      <body>
        <h1>OAuth failed</h1>
        <p>#{message}</p>
      </body>
    </html>
    """
  end

  defp shutdown_bandit(nil), do: :ok

  defp shutdown_bandit(bandit_pid) do
    if Process.alive?(bandit_pid) do
      Supervisor.stop(bandit_pid, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defmodule CallbackPlug do
    @moduledoc false
    @compile {:no_warn_undefined, [Plug.Conn]}

    alias Pristine.OAuth2.CallbackServer

    def init(opts), do: opts

    def call(conn, opts) do
      {conn, status, body} =
        CallbackServer.handle_http_request(opts[:server], conn, opts[:redirect])

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(status, body)
    end
  end
end
