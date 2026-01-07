defmodule Pristine.Test.MockServer do
  @moduledoc """
  Mock HTTP server for testing Pristine-generated clients.

  This module provides a mock server that responds according to manifest
  definitions, enabling integration testing without real API calls.

  ## Usage

      # Start server
      {:ok, server} = MockServer.start(manifest, port: 4001)

      # Set expectations
      MockServer.expect(server, "get_user", %{
        status: 200,
        body: %{id: "123", name: "Test User"}
      })

      # Make requests to http://localhost:4001/...

      # Verify expectations
      MockServer.verify!(server)

      # Stop server
      MockServer.stop(server)

  ## Options

    * `:port` - Port to listen on (0 for random port)
    * `:validate` - Whether to validate request bodies (default: false)
    * `:handlers` - Custom handlers for specific endpoints

  """

  use GenServer

  # Bandit and ThousandIsland are only available in test environment
  @compile {:no_warn_undefined, [Bandit, ThousandIsland]}

  alias Pristine.Manifest
  alias Pristine.Test.Fixtures

  defstruct [:pid, :port, :manifest, :bandit_pid]

  @type t :: %__MODULE__{
          pid: pid(),
          port: non_neg_integer(),
          manifest: Manifest.t(),
          bandit_pid: pid()
        }

  @type option ::
          {:port, non_neg_integer()}
          | {:validate, boolean()}
          | {:handlers, %{String.t() => function()}}

  @doc """
  Starts a mock server for the given manifest.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `opts` - Server options

  ## Options

    * `:port` - Port to listen on (0 for random available port)
    * `:validate` - Whether to validate request bodies (default: false)
    * `:handlers` - Map of endpoint IDs to custom handler functions

  ## Returns

    * `{:ok, server}` - Server struct with port and pid
    * `{:error, reason}` - If server fails to start

  """
  @spec start(Manifest.t(), [option]) :: {:ok, t()} | {:error, term()}
  def start(%Manifest{} = manifest, opts \\ []) do
    port = Keyword.get(opts, :port, 0)
    validate = Keyword.get(opts, :validate, false)
    handlers = Keyword.get(opts, :handlers, %{})

    state = %{
      manifest: manifest,
      validate: validate,
      handlers: handlers,
      expectations: %{},
      history: []
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, state)

    # Start Bandit server
    plug_opts = [server_pid: pid, manifest: manifest]

    bandit_opts = [
      plug: {__MODULE__.Router, plug_opts},
      port: port,
      ip: {127, 0, 0, 1},
      startup_log: false
    ]

    bandit_module = Bandit
    {:ok, bandit_pid} = bandit_module.start_link(bandit_opts)

    # Get the actual port
    thousand_island_module = ThousandIsland
    {:ok, {_, actual_port}} = thousand_island_module.listener_info(bandit_pid)

    {:ok,
     %__MODULE__{
       pid: pid,
       port: actual_port,
       manifest: manifest,
       bandit_pid: bandit_pid
     }}
  end

  @doc """
  Stops the mock server.
  """
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid, bandit_pid: bandit_pid}) do
    # Stop Bandit
    Supervisor.stop(bandit_pid, :normal)
    # Stop GenServer
    GenServer.stop(pid, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Sets an expected response for an endpoint.

  ## Parameters

    * `server` - The mock server
    * `endpoint_id` - The endpoint ID to expect
    * `response` - Response map with optional `:status`, `:body`, `:headers`

  ## Examples

      MockServer.expect(server, "get_user", %{
        status: 200,
        body: %{id: "123", name: "Test User"}
      })

  """
  @spec expect(t(), String.t() | atom(), map()) :: :ok
  def expect(%__MODULE__{pid: pid}, endpoint_id, response) do
    GenServer.call(pid, {:expect, to_string(endpoint_id), response})
  end

  @doc """
  Verifies all expectations were fulfilled.

  Raises if there are unfulfilled expectations.
  """
  @spec verify!(t()) :: :ok
  def verify!(%__MODULE__{pid: pid}) do
    case GenServer.call(pid, :verify) do
      :ok ->
        :ok

      {:error, unfulfilled} ->
        raise "MockServer has unfulfilled expectation for: #{inspect(unfulfilled)}"
    end
  end

  @doc """
  Returns the history of requests received by the server.

  ## Returns

    * List of request maps with `:method`, `:path`, `:path_params`, `:body`

  """
  @spec history(t()) :: [map()]
  def history(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :history)
  end

  # GenServer callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:expect, endpoint_id, response}, _from, state) do
    expectations =
      Map.update(
        state.expectations,
        endpoint_id,
        [response],
        &(&1 ++ [response])
      )

    {:reply, :ok, %{state | expectations: expectations}}
  end

  def handle_call(:verify, _from, state) do
    unfulfilled =
      state.expectations
      |> Enum.filter(fn {_id, responses} -> responses != [] end)
      |> Enum.map(fn {id, _} -> id end)

    result = if Enum.empty?(unfulfilled), do: :ok, else: {:error, unfulfilled}
    {:reply, result, state}
  end

  def handle_call(:history, _from, state) do
    {:reply, Enum.reverse(state.history), state}
  end

  def handle_call({:handle_request, request}, _from, state) do
    {response, state} = process_request(request, state)
    state = %{state | history: [request | state.history]}
    {:reply, response, state}
  end

  # Private functions

  defp process_request(request, state) do
    endpoint_id = request.endpoint_id

    cond do
      # Check for custom handler
      handler = Map.get(state.handlers, endpoint_id) ->
        response = handler.(request)
        {response, state}

      # Check for expectation
      expectations = Map.get(state.expectations, endpoint_id, []) ->
        case expectations do
          [expected | rest] ->
            expectations_map = Map.put(state.expectations, endpoint_id, rest)
            response = normalize_response(expected, request.method)
            {response, %{state | expectations: expectations_map}}

          [] ->
            # Generate fixture response
            response = generate_response(state.manifest, endpoint_id, request.method)
            {response, state}
        end
    end
  end

  defp generate_response(manifest, endpoint_id, method) do
    endpoint = find_endpoint(manifest, endpoint_id)

    body =
      if endpoint && endpoint.response do
        type_def = find_type(manifest, endpoint.response)

        if type_def do
          schema = type_def_to_schema(type_def)
          Fixtures.generate(schema)
        else
          %{}
        end
      else
        %{}
      end

    status = default_status(method)

    %{status: status, body: body, headers: []}
  end

  defp normalize_response(%{status: status} = resp, _method) do
    %{
      status: status,
      body: Map.get(resp, :body, %{}),
      headers: Map.get(resp, :headers, [])
    }
  end

  defp normalize_response(%{body: body}, method) do
    %{status: default_status(method), body: body, headers: []}
  end

  defp normalize_response(resp, method) when is_map(resp) do
    %{status: default_status(method), body: resp, headers: []}
  end

  defp default_status("POST"), do: 201
  defp default_status(_), do: 200

  defp find_endpoint(%Manifest{endpoints: endpoints}, id) do
    Map.get(endpoints, id)
  end

  defp find_type(%Manifest{types: types}, id) do
    Map.get(types, id)
  end

  defp type_def_to_schema(%{fields: fields}) when is_map(fields) do
    properties =
      Enum.map(fields, fn {name, field_def} ->
        type = get_field_type(field_def)
        required = field_required?(field_def)
        {name, type, [required: required]}
      end)

    %{type: :map, properties: properties}
  end

  defp type_def_to_schema(_), do: %{type: :map, properties: []}

  defp get_field_type(field_def) when is_map(field_def) do
    type_str = Map.get(field_def, :type) || Map.get(field_def, "type") || "string"

    case type_str do
      "string" -> :string
      "integer" -> :integer
      "number" -> :number
      "boolean" -> :boolean
      t when is_atom(t) -> t
      _ -> :string
    end
  end

  defp get_field_type(_), do: :string

  defp field_required?(field_def) when is_map(field_def) do
    Map.get(field_def, :required) == true or Map.get(field_def, "required") == true
  end

  defp field_required?(_), do: false

  # Router module
  defmodule Router do
    @moduledoc false
    use Plug.Router

    plug(Plug.Parsers,
      parsers: [:json],
      json_decoder: Jason,
      pass: ["application/json"]
    )

    plug(:match)
    plug(:dispatch)

    match _ do
      server_pid = conn.private[:server_pid]
      manifest = conn.private[:manifest]

      {endpoint, path_params} = match_endpoint(manifest, conn.method, conn.request_path)

      if endpoint do
        request = %{
          endpoint_id: endpoint.id,
          method: conn.method,
          path: conn.request_path,
          path_params: path_params,
          query_params: conn.query_params,
          body: conn.body_params,
          headers: conn.req_headers
        }

        response = GenServer.call(server_pid, {:handle_request, request})

        body =
          if is_map(response.body) do
            Jason.encode!(response.body)
          else
            response.body || ""
          end

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(response.status, body)
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Not found"}))
      end
    end

    defp match_endpoint(%Manifest{endpoints: endpoints}, method, path) do
      method_str = String.upcase(method)

      endpoints
      |> Map.values()
      |> Enum.find_value(fn endpoint ->
        try_match_endpoint(endpoint, method_str, path)
      end) || {nil, %{}}
    end

    defp try_match_endpoint(endpoint, method_str, path) do
      if String.upcase(endpoint.method) == method_str do
        case match_path(endpoint.path, path) do
          {:ok, params} -> {endpoint, params}
          :nomatch -> nil
        end
      end
    end

    defp match_path(template, actual) do
      template_parts = String.split(template, "/", trim: true)
      actual_parts = String.split(actual, "/", trim: true)

      if length(template_parts) == length(actual_parts) do
        match_parts(template_parts, actual_parts, %{})
      else
        :nomatch
      end
    end

    defp match_parts([], [], params), do: {:ok, params}

    defp match_parts(["{" <> rest | t_rest], [value | a_rest], params) do
      param_name = String.trim_trailing(rest, "}")
      match_parts(t_rest, a_rest, Map.put(params, param_name, value))
    end

    defp match_parts([same | t_rest], [same | a_rest], params) do
      match_parts(t_rest, a_rest, params)
    end

    defp match_parts(_, _, _), do: :nomatch

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, opts) do
      conn =
        conn
        |> put_private(:server_pid, Keyword.fetch!(opts, :server_pid))
        |> put_private(:manifest, Keyword.fetch!(opts, :manifest))

      super(conn, opts)
    end
  end
end
