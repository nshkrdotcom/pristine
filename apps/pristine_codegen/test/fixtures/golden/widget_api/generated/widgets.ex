defmodule WidgetAPI.Generated.Widgets do
  @moduledoc """
  Generated Widget API operations for widgets.
  """

  alias Pristine.SDK.OpenAPI.Client, as: OpenAPIClient

  @list_widgets_partition_spec %{
    path: [],
    body: %{mode: :none},
    query: [{"cursor", :cursor}, {"limit", :limit}],
    headers: [{"x-request-id", :request_id}],
    form_data: %{mode: :none}
  }

  @doc "Returns widgets in cursor order."
  @spec list_widgets(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_widgets(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    opts = normalize_request_opts!(opts)
    request = build_list_widgets_request(client, params, opts)
    WidgetAPI.Client.execute_generated_request(client, request)
  end

  @spec stream_list_widgets(term(), map(), keyword()) :: Enumerable.t()
  def stream_list_widgets(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    opts = normalize_request_opts!(opts)

    Stream.resource(
      fn -> build_list_widgets_request(client, params, opts) end,
      fn
        nil ->
          {:halt, nil}

        request when is_map(request) ->
          wrapped_request =
            update_in(request[:opts], fn request_opts ->
              Keyword.put(request_opts || [], :response, :wrapped)
            end)

          case WidgetAPI.Client.execute_generated_request(client, wrapped_request) do
            {:ok, response} ->
              items = List.wrap(OpenAPIClient.items(request, response))
              {items, OpenAPIClient.next_page_request(request, response)}

            {:error, reason} ->
              raise "pagination failed: " <> inspect(reason)
          end
      end,
      fn _state -> :ok end
    )
  end

  defp build_list_widgets_request(client, params, opts)
       when is_map(params) and is_list(opts) do
    _ = client
    partition = OpenAPIClient.partition(params, @list_widgets_partition_spec)

    %{
      id: "widgets/list",
      args: params,
      call: {__MODULE__, :list_widgets},
      opts: opts,
      method: :get,
      path_template: "/v1/widgets",
      path_params: partition.path_params,
      query: partition.query,
      headers: partition.headers,
      body: partition.body,
      form_data: partition.form_data,
      request_schema: nil,
      response_schemas: %{200 => %{collection: true, schema: WidgetAPI.Generated.Types.Widget}},
      auth: %{use_client_default?: true, override: nil, security_schemes: ["bearerAuth"]},
      resource: "widgets",
      retry: "widgets.read",
      circuit_breaker: "widget_api",
      rate_limit: "widget_api",
      telemetry: [:widget_api, :widgets, :list],
      timeout: nil,
      pagination: %{
        default_limit: 100,
        items_path: ["results"],
        request_mapping: %{cursor_param: "cursor", limit_param: "limit"},
        response_mapping: %{cursor_path: ["next_cursor"]},
        strategy: :cursor
      }
    }
  end

  @spec normalize_request_opts!(list()) :: keyword()
  defp normalize_request_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
    else
      raise ArgumentError, "request opts must be a keyword list"
    end
  end
end
