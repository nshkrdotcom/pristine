defmodule Pristine.Operation do
  @moduledoc """
  Normalized runtime operation envelope rendered by generated providers.
  """

  @type key_spec :: {String.t(), atom()}

  @type payload_spec ::
          %{mode: :keys, keys: [key_spec()]}
          | %{mode: :key, key: key_spec()}
          | %{mode: :remaining}
          | %{mode: :none}

  @type partition_spec :: %{
          optional(:auth) => key_spec() | payload_spec(),
          optional(:headers) => [key_spec()],
          optional(:path) => [key_spec()],
          optional(:query) => [key_spec()],
          optional(:body) => payload_spec(),
          optional(:form_data) => payload_spec()
        }

  @type partition_t :: %{
          path_params: map(),
          query: map(),
          headers: map(),
          body: term(),
          form_data: term(),
          auth: term()
        }

  @type auth_t :: %{
          use_client_default?: boolean(),
          override: term(),
          security_schemes: [String.t()]
        }

  @type runtime_t :: %{
          resource: String.t() | nil,
          retry_group: String.t() | nil,
          circuit_breaker: String.t() | nil,
          rate_limit_group: String.t() | nil,
          telemetry_event: term(),
          timeout_ms: non_neg_integer() | nil
        }

  @type pagination_t :: %{
          strategy: :cursor | :keyset | :link_header | :offset_limit | :page_number,
          request_mapping: map(),
          response_mapping: map(),
          default_limit: pos_integer() | nil,
          items_path: [term()] | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          method: atom() | String.t(),
          path_template: String.t(),
          path_params: map(),
          query: map(),
          headers: map(),
          body: term(),
          form_data: term(),
          request_schema: term(),
          response_schemas: map(),
          auth: auth_t(),
          runtime: runtime_t(),
          pagination: pagination_t() | nil
        }

  defstruct id: nil,
            method: nil,
            path_template: nil,
            path_params: %{},
            query: %{},
            headers: %{},
            body: nil,
            form_data: nil,
            request_schema: nil,
            response_schemas: %{},
            auth: %{
              use_client_default?: true,
              override: nil,
              security_schemes: []
            },
            runtime: %{
              resource: nil,
              retry_group: nil,
              circuit_breaker: nil,
              rate_limit_group: nil,
              telemetry_event: nil,
              timeout_ms: nil
            },
            pagination: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs = normalize_attrs(attrs)
    method = Map.get(attrs, :method)
    path_template = Map.get(attrs, :path_template)

    %__MODULE__{
      id: normalize_id(Map.get(attrs, :id), method, path_template),
      method: method,
      path_template: path_template,
      path_params: normalize_string_key_map(Map.get(attrs, :path_params)),
      query: normalize_string_key_map(Map.get(attrs, :query)),
      headers: normalize_string_key_map(Map.get(attrs, :headers)),
      body: normalize_payload_value(Map.get(attrs, :body)),
      form_data: normalize_payload_value(Map.get(attrs, :form_data)),
      request_schema: Map.get(attrs, :request_schema),
      response_schemas: normalize_response_schemas(Map.get(attrs, :response_schemas)),
      auth: normalize_auth(Map.get(attrs, :auth)),
      runtime: normalize_runtime(Map.get(attrs, :runtime)),
      pagination: normalize_pagination(Map.get(attrs, :pagination))
    }
  end

  @spec partition(map(), partition_spec()) :: partition_t()
  def partition(params, spec) when is_map(params) and is_map(spec) do
    {auth, params} = take_auth(params, Map.get(spec, :auth))
    {path_params, params} = take_entries(params, Map.get(spec, :path, []))
    {query, params} = take_entries(params, Map.get(spec, :query, []))
    {headers, params} = take_entries(params, Map.get(spec, :headers, []))
    {body, params} = take_payload(params, Map.get(spec, :body, %{mode: :none}))
    {form_data, _params} = take_payload(params, Map.get(spec, :form_data, %{mode: :none}))

    %{
      path_params: path_params,
      query: query,
      headers: headers,
      body: body,
      form_data: form_data,
      auth: auth
    }
  end

  @spec render_path(String.t(), map()) :: String.t()
  def render_path(path_template, path_params)
      when is_binary(path_template) and is_map(path_params) do
    Regex.replace(~r/\{([^}]+)\}/, path_template, fn _full, name ->
      case Map.fetch(path_params, name) do
        {:ok, value} when not is_nil(value) -> encode_path_value(value)
        _ -> raise KeyError, key: name, term: path_params
      end
    end)
  end

  @spec response_schema(t(), integer() | nil) :: term()
  def response_schema(operation, status \\ nil)

  def response_schema(%__MODULE__{response_schemas: schemas}, nil) do
    response_schema_from_schemas(schemas)
  end

  def response_schema(%__MODULE__{response_schemas: schemas}, status) when is_integer(status) do
    Map.get(schemas, status) ||
      Map.get(schemas, Integer.to_string(status)) ||
      Map.get(schemas, :default) ||
      Map.get(schemas, "default") ||
      response_schema_from_schemas(schemas)
  end

  defp response_schema_from_schemas(schemas) do
    success_schemas =
      schemas
      |> Enum.filter(fn
        {status, _schema} when is_integer(status) -> status >= 200 and status < 300
        _other -> false
      end)
      |> Enum.map(&elem(&1, 1))

    case success_schemas do
      [] -> Map.get(schemas, :default) || Map.get(schemas, "default")
      [schema] -> schema
      many -> {:union, many}
    end
  end

  @spec items(t(), term()) :: term()
  def items(%__MODULE__{pagination: nil}, response_or_body), do: response_body(response_or_body)

  def items(%__MODULE__{pagination: %{items_path: nil}}, response_or_body),
    do: response_body(response_or_body)

  def items(%__MODULE__{pagination: %{items_path: items_path}}, response_or_body) do
    response_or_body
    |> response_body()
    |> get_path_value(items_path)
  end

  @spec next_page(t(), term()) :: t() | nil
  def next_page(%__MODULE__{pagination: nil}, _response_or_body), do: nil

  def next_page(%__MODULE__{} = operation, response_or_body) do
    case operation.pagination.strategy do
      :cursor ->
        build_cursor_page(operation, response_body(response_or_body), :cursor_path)

      :keyset ->
        build_cursor_page(operation, response_body(response_or_body), :cursor_path)

      :link_header ->
        build_link_header_page(operation, response_or_body)

      :offset_limit ->
        build_offset_page(operation, response_body(response_or_body))

      :page_number ->
        build_page_number_page(operation, response_body(response_or_body))
    end
  end

  defp build_cursor_page(%__MODULE__{} = operation, body, cursor_key) do
    cursor_path = fetch_mapping(operation.pagination.response_mapping, cursor_key)
    cursor = get_path_value(body, cursor_path)
    cursor_param = fetch_mapping(operation.pagination.request_mapping, :cursor_param)

    cursor_location =
      fetch_mapping(operation.pagination.request_mapping, :cursor_location) || :query

    if blank?(cursor) do
      nil
    else
      case cursor_location do
        :body ->
          body =
            operation.body
            |> maybe_put_limit_payload(operation.pagination)
            |> Map.put(cursor_param, cursor)

          %__MODULE__{operation | body: body}

        _other ->
          query =
            operation.query
            |> maybe_put_limit(operation.pagination)
            |> Map.put(cursor_param, cursor)

          %__MODULE__{operation | query: query}
      end
    end
  end

  defp build_link_header_page(%__MODULE__{} = operation, response_or_body) do
    header_name = fetch_mapping(operation.pagination.response_mapping, :link_header) || "link"

    response_or_body
    |> response_headers()
    |> header_value(header_name)
    |> next_link_url()
    |> case do
      nil ->
        nil

      url ->
        uri = URI.parse(url)
        next_query = if is_binary(uri.query), do: URI.decode_query(uri.query), else: %{}

        query =
          operation.query
          |> normalize_string_key_map()
          |> Map.merge(next_query)
          |> maybe_put_limit(operation.pagination)

        %__MODULE__{
          operation
          | path_template: uri.path || operation.path_template,
            path_params: %{},
            query: query
        }
    end
  end

  defp build_offset_page(%__MODULE__{} = operation, body) do
    mapping = operation.pagination.request_mapping
    response_mapping = operation.pagination.response_mapping
    offset_param = fetch_mapping(mapping, :offset_param)

    next_offset =
      get_path_value(body, fetch_mapping(response_mapping, :next_offset_path)) ||
        infer_offset(operation.query, mapping, items(operation, body))

    if is_nil(next_offset) do
      nil
    else
      query =
        operation.query
        |> maybe_put_limit(operation.pagination)
        |> Map.put(offset_param, next_offset)

      %__MODULE__{operation | query: query}
    end
  end

  defp build_page_number_page(%__MODULE__{} = operation, body) do
    mapping = operation.pagination.request_mapping
    response_mapping = operation.pagination.response_mapping
    page_param = fetch_mapping(mapping, :page_param)

    next_page =
      get_path_value(body, fetch_mapping(response_mapping, :next_page_path)) ||
        infer_page_number(operation.query, page_param, items(operation, body))

    if is_nil(next_page) do
      nil
    else
      query =
        operation.query
        |> maybe_put_limit(operation.pagination)
        |> Map.put(page_param, next_page)

      %__MODULE__{operation | query: query}
    end
  end

  defp maybe_put_limit(query, %{default_limit: nil}), do: normalize_string_key_map(query)

  defp maybe_put_limit(query, %{request_mapping: mapping, default_limit: limit}) do
    query = normalize_string_key_map(query)
    limit_param = fetch_mapping(mapping, :limit_param)

    cond do
      is_nil(limit_param) -> query
      Map.has_key?(query, limit_param) -> query
      true -> Map.put(query, limit_param, limit)
    end
  end

  defp maybe_put_limit_payload(body, %{default_limit: nil}), do: normalize_payload_map(body)

  defp maybe_put_limit_payload(body, %{request_mapping: mapping, default_limit: limit}) do
    body = normalize_payload_map(body)
    limit_param = fetch_mapping(mapping, :limit_param)

    cond do
      is_nil(limit_param) -> body
      Map.has_key?(body, limit_param) -> body
      true -> Map.put(body, limit_param, limit)
    end
  end

  defp infer_offset(query, mapping, items) when is_list(items) do
    offset =
      parse_integer(
        Map.get(normalize_string_key_map(query), fetch_mapping(mapping, :offset_param))
      )

    limit =
      parse_integer(
        Map.get(normalize_string_key_map(query), fetch_mapping(mapping, :limit_param))
      )

    case {offset, limit, items} do
      {offset, limit, [_ | _]} when is_integer(offset) and is_integer(limit) -> offset + limit
      {nil, limit, [_ | _]} when is_integer(limit) -> limit
      _ -> nil
    end
  end

  defp infer_offset(_query, _mapping, _items), do: nil

  defp infer_page_number(query, page_param, items) when is_list(items) do
    query = normalize_string_key_map(query)
    current_page = parse_integer(Map.get(query, page_param)) || 1

    case items do
      [] -> nil
      [_ | _] -> current_page + 1
      _ -> nil
    end
  end

  defp infer_page_number(_query, _page_param, _items), do: nil

  defp next_link_url(nil), do: nil

  defp next_link_url(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.find_value(fn segment ->
      case Regex.run(~r/<([^>]+)>\s*;\s*rel=\"([^\"]+)\"/, String.trim(segment)) do
        [_, url, "next"] -> url
        _ -> nil
      end
    end)
  end

  defp next_link_url(_value), do: nil

  defp header_value(headers, target) when is_map(headers) do
    target = String.downcase(to_string(target))

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == target do
        value
      end
    end)
  end

  defp header_value(_headers, _target), do: nil

  defp response_body(%Pristine.Response{body: body}), do: body
  defp response_body(%{body: body}) when is_map(body) or is_list(body), do: body
  defp response_body(body), do: body

  defp response_headers(%Pristine.Response{headers: headers}), do: headers
  defp response_headers(%{headers: headers}) when is_map(headers), do: headers
  defp response_headers(_response_or_body), do: %{}

  defp fetch_mapping(mapping, key) when is_map(mapping) do
    Map.get(mapping, key) || Map.get(mapping, Atom.to_string(key))
  end

  defp fetch_mapping(_mapping, _key), do: nil

  defp get_path_value(nil, _path), do: nil
  defp get_path_value(data, nil), do: data

  defp get_path_value(data, path) when is_binary(path) do
    get_path_value(data, String.split(path, ".", trim: true))
  end

  defp get_path_value(data, []), do: data

  defp get_path_value(data, [segment | rest]) when is_map(data) do
    value =
      Enum.find_value(data, fn {key, value} ->
        if to_string(key) == to_string(segment) do
          value
        end
      end)

    get_path_value(value, rest)
  end

  defp get_path_value(data, [segment | rest]) when is_list(data) and is_integer(segment) do
    data |> Enum.at(segment) |> get_path_value(rest)
  end

  defp get_path_value(_data, _path), do: nil

  defp normalize_attrs(attrs) when is_list(attrs), do: Enum.into(attrs, %{})
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(_attrs), do: %{}

  defp normalize_id(nil, method, path_template) do
    method_name =
      method
      |> to_string()
      |> String.downcase()

    "#{method_name}:#{path_template}"
  end

  defp normalize_id(id, _method, _path_template), do: to_string(id)

  defp normalize_auth(nil) do
    %{
      use_client_default?: true,
      override: nil,
      security_schemes: []
    }
  end

  defp normalize_auth(auth) when is_map(auth) do
    %{
      use_client_default?:
        Map.get(auth, :use_client_default?, Map.get(auth, "use_client_default?", true)),
      override: Map.get(auth, :override, Map.get(auth, "override")),
      security_schemes:
        auth
        |> Map.get(:security_schemes, Map.get(auth, "security_schemes", []))
        |> normalize_security_schemes()
    }
  end

  defp normalize_auth(_auth), do: normalize_auth(nil)

  defp normalize_runtime(nil) do
    %{
      resource: nil,
      retry_group: nil,
      circuit_breaker: nil,
      rate_limit_group: nil,
      telemetry_event: nil,
      timeout_ms: nil
    }
  end

  defp normalize_runtime(runtime) when is_map(runtime) do
    %{
      resource: fetch_value(runtime, :resource),
      retry_group: fetch_value(runtime, :retry_group),
      circuit_breaker: fetch_value(runtime, :circuit_breaker),
      rate_limit_group: fetch_value(runtime, :rate_limit_group),
      telemetry_event: fetch_value(runtime, :telemetry_event),
      timeout_ms: fetch_value(runtime, :timeout_ms)
    }
  end

  defp normalize_runtime(_runtime), do: normalize_runtime(nil)

  defp normalize_pagination(nil), do: nil

  defp normalize_pagination(pagination) when is_map(pagination) do
    %{
      strategy: fetch_value(pagination, :strategy),
      request_mapping: normalize_string_key_map(fetch_value(pagination, :request_mapping)),
      response_mapping: normalize_string_key_map(fetch_value(pagination, :response_mapping)),
      default_limit: fetch_value(pagination, :default_limit),
      items_path: normalize_items_path(fetch_value(pagination, :items_path))
    }
  end

  defp normalize_pagination(_pagination), do: nil

  defp normalize_items_path(nil), do: nil
  defp normalize_items_path(path) when is_list(path), do: path
  defp normalize_items_path(path) when is_binary(path), do: String.split(path, ".", trim: true)
  defp normalize_items_path(_path), do: nil

  defp normalize_response_schemas(nil), do: %{}

  defp normalize_response_schemas(schemas) when is_map(schemas) do
    Map.new(schemas, fn
      {key, value} when is_integer(key) ->
        {key, value}

      {key, value} when key in [:default, "default"] ->
        {:default, value}

      {key, value} when is_binary(key) ->
        case Integer.parse(key) do
          {status, ""} -> {status, value}
          _ -> {key, value}
        end

      {key, value} ->
        {key, value}
    end)
  end

  defp normalize_response_schemas(_schemas), do: %{}

  defp normalize_security_schemes(schemes) when is_list(schemes),
    do: Enum.map(schemes, &to_string/1)

  defp normalize_security_schemes(_schemes), do: []

  defp fetch_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp normalize_string_key_map(nil), do: %{}

  defp normalize_string_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_string_key_map(map) when is_list(map) do
    if Keyword.keyword?(map) do
      Map.new(map, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_string_key_map(_map), do: %{}

  defp normalize_payload_value(value) when value in [%{}, []], do: nil
  defp normalize_payload_value(value), do: value

  defp take_payload(params, %{mode: :none}), do: {nil, params}

  defp take_payload(params, %{mode: :remaining}) do
    payload = stringify_map(params)
    {empty_to_nil(payload), %{}}
  end

  defp take_payload(params, %{mode: :keys, keys: keys}) do
    {payload, params} = take_entries(params, keys)
    {empty_to_nil(payload), params}
  end

  defp take_payload(params, %{mode: :key, key: key}) do
    case take_value(params, key) do
      {nil, params} -> {nil, params}
      {value, params} -> {normalize_payload(value), params}
    end
  end

  defp take_entries(params, keys) do
    Enum.reduce(keys, {%{}, params}, fn key, {acc, params} ->
      case take_value(params, key) do
        {nil, params} ->
          {acc, params}

        {value, params} ->
          {Map.put(acc, elem(key, 0), value), params}
      end
    end)
  end

  defp take_auth(params, nil), do: {nil, params}
  defp take_auth(params, {string_key, atom_key}), do: take_value(params, {string_key, atom_key})

  defp take_auth(params, %{mode: mode} = spec) when mode in [:none, :remaining, :keys, :key] do
    take_payload(params, spec)
  end

  defp take_value(params, nil), do: {nil, params}

  defp take_value(params, {string_key, atom_key}) do
    cond do
      Map.has_key?(params, atom_key) ->
        {Map.fetch!(params, atom_key), Map.delete(params, atom_key)}

      Map.has_key?(params, string_key) ->
        {Map.fetch!(params, string_key), Map.delete(params, string_key)}

      true ->
        {nil, params}
    end
  end

  defp normalize_payload(value) when is_map(value), do: stringify_map(value)
  defp normalize_payload(value), do: value

  defp normalize_payload_map(value) when is_map(value), do: stringify_map(value)
  defp normalize_payload_map(_value), do: %{}

  defp stringify_map(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), item} end)
  end

  defp empty_to_nil(map) when is_map(map) and map_size(map) == 0, do: nil
  defp empty_to_nil(value), do: value

  defp encode_path_value(value) when is_list(value) do
    value
    |> Enum.map_join(",", &to_string/1)
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp encode_path_value(value) do
    value
    |> to_string()
    |> URI.encode(&URI.char_unreserved?/1)
  end
end
