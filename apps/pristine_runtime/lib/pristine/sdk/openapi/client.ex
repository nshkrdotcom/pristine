defmodule Pristine.SDK.OpenAPI.Client do
  @moduledoc """
  SDK-facing request contracts for generated provider SDKs.
  """

  alias Pristine.Operation

  @type request_t :: %{
          required(:method) => atom() | String.t(),
          required(:path_template) => String.t(),
          optional(:id) => String.t() | nil,
          optional(:path_params) => map(),
          optional(:query) => map(),
          optional(:body) => term() | nil,
          optional(:form_data) => term() | nil,
          optional(:headers) => map(),
          optional(:auth) => map() | term() | nil,
          optional(:security) => [map()] | nil,
          optional(:request_schema) => term() | nil,
          optional(:response_schema) => term() | nil,
          optional(:response_schemas) => map(),
          optional(:pagination) => map() | nil,
          optional(:resource) => String.t() | nil,
          optional(:retry) => String.t() | nil,
          optional(:circuit_breaker) => String.t() | nil,
          optional(:rate_limit) => String.t() | nil,
          optional(:telemetry) => term(),
          optional(:timeout) => pos_integer() | nil,
          optional(:use_default_auth) => boolean(),
          optional(:opts) => keyword(),
          optional(:args) => map(),
          optional(:call) => {module(), atom()}
        }

  @type request_spec_t :: %{
          required(:method) => atom() | String.t(),
          required(:path) => String.t(),
          required(:path_params) => map(),
          required(:query) => map(),
          required(:body) => term() | nil,
          required(:form_data) => term() | nil,
          required(:headers) => map() | nil,
          required(:auth) => term() | nil,
          required(:security) => [map()] | nil,
          required(:request_schema) => term() | nil,
          required(:response_schema) => term() | nil,
          required(:id) => String.t() | nil,
          optional(:circuit_breaker) => String.t() | nil,
          optional(:rate_limit) => String.t() | nil,
          optional(:resource) => String.t() | nil,
          optional(:retry) => String.t() | nil,
          optional(:telemetry) => term(),
          optional(:timeout) => pos_integer() | nil,
          optional(:use_default_auth) => boolean(),
          optional(:pagination) => map() | nil
        }

  @spec request(request_t()) :: {:ok, request_t()}
  def request(request) when is_map(request), do: {:ok, request}

  @spec partition(map(), Operation.partition_spec()) :: Operation.partition_t()
  def partition(params, spec) when is_map(params) and is_map(spec) do
    Operation.partition(params, spec)
  end

  @spec to_request_spec(request_t()) :: request_spec_t()
  def to_request_spec(%{path_template: path_template} = request) when is_binary(path_template) do
    %{
      method: Map.get(request, :method),
      path: path_template,
      path_params: normalize_map(Map.get(request, :path_params)),
      query: normalize_map(Map.get(request, :query)),
      body: request_body(request),
      form_data: request_form_data(request),
      headers: normalize_map(Map.get(request, :headers)),
      auth: request_auth_override(request),
      security: request_security(request),
      request_schema: Map.get(request, :request_schema),
      response_schema: response_schema(request),
      id: request_id(request),
      use_default_auth: use_default_auth?(request),
      pagination: Map.get(request, :pagination)
    }
    |> forward_optional_fields(request, [
      :circuit_breaker,
      :rate_limit,
      :resource,
      :retry,
      :telemetry,
      :timeout
    ])
  end

  def to_request_spec(request) do
    raise KeyError, key: :path_template, term: request
  end

  @spec items(request_t(), term()) :: term()
  def items(request, response) when is_map(request) do
    request
    |> to_operation()
    |> Operation.items(response)
  end

  @spec next_page_request(request_t(), term()) :: request_t() | nil
  def next_page_request(request, response) when is_map(request) do
    case request |> to_operation() |> Operation.next_page(response) do
      %Operation{} = next_operation -> from_operation(request, next_operation)
      nil -> nil
    end
  end

  @spec to_operation(request_t()) :: Operation.t()
  def to_operation(request) when is_map(request) do
    Operation.new(%{
      id: request_id(request),
      method: Map.get(request, :method),
      path_template: Map.get(request, :path_template),
      path_params: normalize_map(Map.get(request, :path_params)),
      query: normalize_map(Map.get(request, :query)),
      headers: normalize_map(Map.get(request, :headers)),
      body: request_body(request),
      form_data: request_form_data(request),
      request_schema: Map.get(request, :request_schema),
      response_schemas: response_schemas(request),
      auth: operation_auth(request),
      runtime: %{
        resource: Map.get(request, :resource),
        retry_group: Map.get(request, :retry),
        circuit_breaker: Map.get(request, :circuit_breaker),
        rate_limit_group: Map.get(request, :rate_limit),
        telemetry_event: Map.get(request, :telemetry),
        timeout_ms: Map.get(request, :timeout)
      },
      pagination: Map.get(request, :pagination)
    })
  end

  defp from_operation(request, %Operation{} = operation) do
    request
    |> Map.put(:id, operation.id)
    |> Map.put(:method, operation.method)
    |> Map.put(:path_template, operation.path_template)
    |> Map.put(:path_params, operation.path_params)
    |> Map.put(:query, operation.query)
    |> Map.put(:headers, operation.headers)
    |> Map.put(:body, operation.body)
    |> Map.put(:form_data, operation.form_data)
    |> Map.put(:request_schema, operation.request_schema)
    |> Map.put(:response_schemas, operation.response_schemas)
    |> Map.put(:pagination, operation.pagination)
    |> Map.put(
      :auth,
      %{
        use_client_default?: operation.auth.use_client_default?,
        override: operation.auth.override,
        security_schemes: operation.auth.security_schemes
      }
    )
    |> Map.put(:resource, operation.runtime.resource)
    |> Map.put(:retry, operation.runtime.retry_group)
    |> Map.put(:circuit_breaker, operation.runtime.circuit_breaker)
    |> Map.put(:rate_limit, operation.runtime.rate_limit_group)
    |> Map.put(:telemetry, operation.runtime.telemetry_event)
    |> Map.put(:timeout, operation.runtime.timeout_ms)
  end

  defp operation_auth(request) do
    case Map.get(request, :auth) do
      %{use_client_default?: _use_client_default?} = auth ->
        %{
          use_client_default?: Map.get(auth, :use_client_default?, true),
          override: Map.get(auth, :override),
          security_schemes: Map.get(auth, :security_schemes, [])
        }

      override ->
        %{
          use_client_default?: use_default_auth?(request),
          override: override,
          security_schemes: security_schemes_from_request(request)
        }
    end
  end

  defp request_auth_override(%{auth: %{override: override}}), do: override
  defp request_auth_override(%{auth: override}), do: override
  defp request_auth_override(_request), do: nil

  defp request_security(%{security: security}) when is_list(security), do: security

  defp request_security(request) do
    case security_schemes_from_request(request) do
      [] -> nil
      schemes -> Enum.map(schemes, &%{to_string(&1) => []})
    end
  end

  defp security_schemes_from_request(%{auth: %{security_schemes: schemes}}) when is_list(schemes),
    do: schemes

  defp security_schemes_from_request(_request), do: []

  defp use_default_auth?(%{auth: %{use_client_default?: use_client_default?}}),
    do: use_client_default?

  defp use_default_auth?(%{use_default_auth: use_default_auth?}), do: use_default_auth?
  defp use_default_auth?(_request), do: true

  defp response_schemas(%{response_schemas: %{} = response_schemas}), do: response_schemas
  defp response_schemas(%{response_schema: nil}), do: %{}
  defp response_schemas(%{response_schema: response_schema}), do: %{default: response_schema}
  defp response_schemas(_request), do: %{}

  defp response_schema(%{response_schemas: %{} = response_schemas}) do
    success_schemas =
      response_schemas
      |> Enum.filter(fn
        {status, _schema} when is_integer(status) -> status >= 200 and status < 300
        {_status, _schema} -> false
      end)
      |> Enum.map(&elem(&1, 1))

    case success_schemas do
      [] -> Map.get(response_schemas, :default) || Map.get(response_schemas, "default")
      [schema] -> schema
      schemas -> {:union, schemas}
    end
  end

  defp response_schema(%{response_schema: response_schema}), do: response_schema
  defp response_schema(_request), do: nil

  defp request_id(%{id: id}) when is_binary(id), do: id

  defp request_id(%{call: {module, function}})
       when is_atom(module) and is_atom(function) do
    module
    |> Module.split()
    |> Enum.join(".")
    |> Kernel.<>(".")
    |> Kernel.<>(Atom.to_string(function))
  end

  defp request_id(_request), do: nil

  defp request_body(request) do
    case Map.get(request, :body) do
      %{} = body when map_size(body) == 0 -> nil
      body -> body
    end
  end

  defp request_form_data(request) do
    case Map.get(request, :form_data) do
      %{} = form_data when map_size(form_data) == 0 -> nil
      form_data -> form_data
    end
  end

  defp normalize_map(nil), do: %{}

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(map) when is_list(map) do
    if Keyword.keyword?(map) do
      Map.new(map, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_map(_map), do: %{}

  defp forward_optional_fields(spec, request, fields) do
    Enum.reduce(fields, spec, fn field, acc ->
      if Map.has_key?(request, field) do
        Map.put(acc, field, Map.get(request, field))
      else
        acc
      end
    end)
  end
end
