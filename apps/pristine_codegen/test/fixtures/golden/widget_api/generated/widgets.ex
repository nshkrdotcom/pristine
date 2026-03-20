defmodule WidgetAPI.Generated.Widgets do
  @moduledoc """
  Generated Widget API operations for widgets.
  """

  @list_widgets_partition_spec %{
    path: [],
    body: %{mode: :none},
    form_data: %{mode: :none},
    query: [{"cursor", :cursor}, {"limit", :limit}],
    headers: [{"x-request-id", :request_id}]
  }

  @doc "Returns widgets in cursor order."
  @spec list_widgets(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_widgets(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    operation = build_list_widgets_operation(params)
    Pristine.execute(client, operation, opts)
  end

  @spec stream_list_widgets(term(), map(), keyword()) :: Enumerable.t()
  def stream_list_widgets(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    Stream.resource(
      fn -> build_list_widgets_operation(params) end,
      fn
        nil ->
          {:halt, nil}

        %Pristine.Operation{} = operation ->
          case Pristine.execute(client, operation, opts) do
            {:ok, response} ->
              items = List.wrap(Pristine.Operation.items(operation, response))
              {items, Pristine.Operation.next_page(operation, response)}

            {:error, reason} ->
              raise "pagination failed: " <> inspect(reason)
          end
      end,
      fn _state -> :ok end
    )
  end

  defp build_list_widgets_operation(params) when is_map(params) do
    partition = Pristine.Operation.partition(params, @list_widgets_partition_spec)

    Pristine.Operation.new(%{
      id: "widgets/list",
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
      runtime: %{
        circuit_breaker: "widget_api",
        rate_limit_group: "widget_api",
        resource: "widgets",
        retry_group: "widgets.read",
        telemetry_event: [:widget_api, :widgets, :list],
        timeout_ms: nil
      },
      pagination: %{
        default_limit: 100,
        items_path: ["results"],
        request_mapping: %{cursor_param: "cursor", limit_param: "limit"},
        response_mapping: %{cursor_path: ["next_cursor"]},
        strategy: :cursor
      }
    })
  end
end
