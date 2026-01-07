defmodule Pristine.Codegen.Resource do
  @moduledoc """
  Generates resource modules for grouped endpoints.

  Resource modules provide a namespace for related API endpoints,
  following the pattern `client.models.create()` seen in modern SDKs.
  """

  alias Pristine.Codegen.Type
  alias Pristine.Manifest.Endpoint

  @doc """
  Groups endpoints by their resource field.

  Returns a map where keys are resource names (or nil for ungrouped)
  and values are lists of endpoints.
  """
  @spec group_by_resource([Endpoint.t()]) :: %{(String.t() | nil) => [Endpoint.t()]}
  def group_by_resource(endpoints) do
    Enum.group_by(endpoints, & &1.resource)
  end

  @doc """
  Renders all resource modules for a list of endpoints.

  Returns a map of module name to source code. Endpoints with
  `resource: nil` are excluded.
  """
  @spec render_all_resource_modules(String.t(), [Endpoint.t()], map()) :: %{
          String.t() => String.t()
        }
  def render_all_resource_modules(namespace, endpoints, types \\ %{}) do
    endpoints
    |> group_by_resource()
    |> Enum.reject(fn {resource, _} -> is_nil(resource) end)
    |> Enum.map(fn {resource, eps} ->
      module_name = resource_to_module_name(namespace, resource)
      code = render_resource_module(module_name, resource, eps, types)
      {module_name, code}
    end)
    |> Map.new()
  end

  @doc """
  Renders a single resource module.
  """
  @spec render_resource_module(String.t(), String.t(), [Endpoint.t()], map()) :: String.t()
  def render_resource_module(module_name, resource, endpoints, types \\ %{}) do
    resource_title = resource |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
    base_namespace = base_namespace(module_name, resource)
    client_module = "#{base_namespace}.Client"
    types_namespace = "#{base_namespace}.Types"

    # Analyze which helpers are needed
    helper_usage = analyze_helper_usage(endpoints, types)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{resource_title} resource endpoints.

      This module provides functions for interacting with #{resource} resources.
      \"\"\"

      defstruct [:context]

      @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

      @doc "Create a resource module instance with the given client."
      @spec with_client(%{context: Pristine.Core.Context.t()}) :: t()
      def with_client(%{context: context}) do
        %__MODULE__{context: context}
      end

    #{render_endpoint_functions(endpoints, types, types_namespace, client_module)}
    #{render_helpers(helper_usage)}end
    """
  end

  defp analyze_helper_usage(endpoints, types) do
    Enum.reduce(
      endpoints,
      %{maybe_put: false, merge_path_params: false, encode_ref: false},
      fn endpoint, acc ->
        path_params = extract_path_params(endpoint.path)
        fields = request_fields(endpoint, types)
        {_required, optional, _literal} = split_fields(fields, path_params)

        acc
        |> Map.put(:maybe_put, acc.maybe_put or optional != [])
        |> Map.put(:merge_path_params, acc.merge_path_params or path_params != [])
        |> Map.put(:encode_ref, acc.encode_ref or has_ref_fields?(fields, types))
      end
    )
  end

  defp has_ref_fields?(fields, types) do
    Enum.any?(fields, fn field ->
      type_ref = get_value(field.defn, :type_ref) || get_value(field.defn, "type_ref")
      type = normalize_key(get_value(field.defn, :type) || get_value(field.defn, "type") || "")
      items = get_value(field.defn, :items) || get_value(field.defn, "items")

      not is_nil(type_ref) or
        (type == "array" and not is_nil(list_item_ref(items, types)))
    end)
  end

  defp render_helpers(usage) do
    helpers = []

    helpers =
      if usage.maybe_put do
        [
          """
            defp maybe_put(payload, _key, nil), do: payload
            defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
            defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
          """
          | helpers
        ]
      else
        helpers
      end

    helpers =
      if usage.merge_path_params do
        [
          """
            defp merge_path_params(opts, path_params) do
              existing = Keyword.get(opts, :path_params, %{})
              Keyword.put(opts, :path_params, Map.merge(existing, path_params))
            end
          """
          | helpers
        ]
      else
        helpers
      end

    helpers =
      if usage.encode_ref do
        [
          """
            defp encode_ref(nil, _module), do: nil
            defp encode_ref(value, module) do
              if function_exported?(module, :encode, 1) do
                module.encode(value)
              else
                value
              end
            end

            defp encode_ref_list(nil, _module), do: nil
            defp encode_ref_list(values, module) when is_list(values) do
              Enum.map(values, &encode_ref(&1, module))
            end
          """
          | helpers
        ]
      else
        helpers
      end

    Enum.join(helpers, "\n")
  end

  @doc """
  Converts a resource name to a module name.

  ## Examples

      iex> Resource.resource_to_module_name("MyAPI", "models")
      "MyAPI.Models"

      iex> Resource.resource_to_module_name("MyAPI", "my_resource")
      "MyAPI.MyResource"
  """
  @spec resource_to_module_name(String.t(), String.t()) :: String.t()
  def resource_to_module_name(namespace, resource) do
    module_part = resource |> String.split("_") |> Enum.map_join(&String.capitalize/1)
    "#{namespace}.#{module_part}"
  end

  # Private functions

  defp render_endpoint_functions(endpoints, types, types_namespace, client_module) do
    Enum.map_join(endpoints, "\n", fn endpoint ->
      sync = render_endpoint_function(endpoint, types, types_namespace, client_module, :sync)

      async =
        if endpoint.async do
          render_endpoint_function(endpoint, types, types_namespace, client_module, :async)
        else
          ""
        end

      stream =
        if endpoint.streaming do
          render_endpoint_function(endpoint, types, types_namespace, client_module, :stream)
        else
          ""
        end

      Enum.join([sync, async, stream], "\n")
    end)
  end

  defp render_endpoint_function(endpoint, types, types_namespace, client_module, mode) do
    fn_name = function_name(endpoint.id, mode)
    path_params = extract_path_params(endpoint.path)
    fields = request_fields(endpoint, types)
    {required_fields, optional_fields, literal_fields} = split_fields(fields, path_params)

    params =
      path_params
      |> Enum.map(&String.to_atom/1)
      |> Kernel.++(Enum.map(required_fields, &String.to_atom(&1.name)))

    params_with_context = ["%__MODULE__{context: context}" | Enum.map(params, &to_string/1)]
    param_list = Enum.join(params_with_context, ", ")

    doc = render_doc(endpoint, params, optional_fields, mode)
    spec = render_spec(fn_name, params, endpoint, types_namespace, types, mode)
    call_opts = %{client_module: client_module, mode: mode}

    body =
      render_body(
        endpoint,
        required_fields,
        optional_fields,
        literal_fields,
        path_params,
        types_namespace,
        types,
        call_opts
      )

    """
      #{doc}#{spec}  def #{fn_name}(#{param_list}, opts \\\\ []) do
    #{body}  end
    """
  end

  defp render_doc(endpoint, params, optional_fields, mode) do
    description = endpoint.description || ""

    param_lines =
      params
      |> Enum.map(fn param -> "  * `#{param}` - Required parameter." end)

    optional_lines =
      optional_fields
      |> Enum.map(fn field -> "    * `:#{field.name}` - Optional parameter." end)

    optional_lines =
      optional_lines ++
        if(endpoint.idempotency,
          do: ["    * `:idempotency_key` - Idempotency key override."],
          else: []
        ) ++
        if endpoint.timeout, do: ["    * `:timeout` - Request timeout in milliseconds."], else: []

    returns = render_returns(mode)

    param_section =
      if param_lines != [] or optional_lines != [] do
        [
          "## Parameters",
          Enum.join(param_lines, "\n"),
          if(optional_lines == [], do: nil, else: "  * `opts` - Optional parameters:"),
          if(optional_lines == [], do: nil, else: Enum.join(optional_lines, "\n"))
        ]
      else
        []
      end

    doc_body =
      [
        description,
        param_section |> List.flatten() |> Enum.reject(&is_nil/1) |> Enum.join("\n"),
        "## Returns",
        "  * `#{returns}`",
        "## Example",
        "    #{example_call(endpoint.id, params, mode)}"
      ]
      |> Enum.reject(&(&1 == "" || is_nil(&1)))
      |> Enum.join("\n")

    """
    @doc \"\"\"
    #{doc_body}
    \"\"\"
    """
  end

  defp render_returns(:sync), do: "{:ok, response} | {:error, Pristine.Error.t()}"
  defp render_returns(:async), do: "{:ok, Task.t()} | {:error, Pristine.Error.t()}"

  defp render_returns(:stream),
    do: "{:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}"

  defp example_call(endpoint_id, params, mode) do
    suffix =
      case mode do
        :sync -> ""
        :async -> "_async"
        :stream -> "_stream"
      end

    args = Enum.map_join(params, ", ", &to_string/1)

    if args == "" do
      "resource.#{endpoint_id}#{suffix}()"
    else
      "resource.#{endpoint_id}#{suffix}(#{args}, [])"
    end
  end

  defp render_spec(fn_name, params, endpoint, types_namespace, types, mode) do
    param_specs =
      Enum.map_join(params, ", ", fn param ->
        param
        |> field_def_for_param(endpoint, types)
        |> typespec_for_field(types_namespace, types)
      end)

    return_type =
      case mode do
        :stream -> "Pristine.Core.StreamResponse.t()"
        :async -> "Task.t()"
        :sync -> response_typespec(endpoint.response, types_namespace)
      end

    spec_params =
      if param_specs == "" do
        "t(), keyword()"
      else
        "t(), #{param_specs}, keyword()"
      end

    """
    @spec #{fn_name}(#{spec_params}) :: {:ok, #{return_type}} | {:error, Pristine.Error.t()}
    """
  end

  defp render_body(
         endpoint,
         required_fields,
         optional_fields,
         literal_fields,
         path_params,
         types_namespace,
         types,
         %{client_module: client_module, mode: mode}
       ) do
    payload_entries =
      required_fields
      |> Enum.map(fn field ->
        value = field_value_expr(field, types_namespace, types, field.name)
        "        \"#{field.name}\" => #{value}"
      end)

    literal_entries =
      Enum.map(literal_fields, fn field ->
        value = get_value(field.defn, :value) || get_value(field.defn, "value")
        "        \"#{field.name}\" => #{inspect(value)}"
      end)

    base_payload =
      if payload_entries == [] and literal_entries == [] do
        "      %{}"
      else
        """
          %{
        #{Enum.join(payload_entries ++ literal_entries, ",\n")}
          }
        """
      end

    optional_pipeline =
      Enum.map(optional_fields, fn field ->
        value_expr = "Keyword.get(opts, :#{field.name})"
        encoded = field_value_expr(field, types_namespace, types, value_expr)
        "      |> maybe_put(\"#{field.name}\", #{encoded})"
      end)

    path_params_expr =
      if path_params == [] do
        ""
      else
        entries =
          Enum.map(path_params, fn name ->
            "        \"#{name}\" => #{name}"
          end)

        """
        path_params = %{
        #{Enum.join(entries, ",\n")}
        }

        opts = merge_path_params(opts, path_params)
        """
      end

    pipeline_call =
      case mode do
        :stream -> "Pristine.Runtime.execute_stream"
        :async -> "Pristine.Runtime.execute_future"
        :sync -> "Pristine.Runtime.execute"
      end

    """
      payload =
    #{base_payload}
    #{Enum.join(optional_pipeline, "\n")}

    #{path_params_expr}      #{pipeline_call}(#{client_module}.manifest(), #{inspect(endpoint.id)}, payload, context, opts)
    """
  end

  defp field_value_expr(field, types_namespace, types, value_expr) do
    case field_ref_info(field, types, types_namespace) do
      {_, :single, module} -> "encode_ref(#{value_expr}, #{module})"
      {_, :list, module} -> "encode_ref_list(#{value_expr}, #{module})"
      _ -> value_expr
    end
  end

  defp response_typespec(nil, _types_namespace), do: "term()"
  defp response_typespec("", _types_namespace), do: "term()"
  defp response_typespec(type_name, types_namespace), do: "#{types_namespace}.#{type_name}.t()"

  defp typespec_for_field(nil, _types_namespace, _types), do: "term()"

  defp typespec_for_field(field_def, types_namespace, types) do
    field_def
    |> field_typespec_data()
    |> field_typespec(types_namespace, types)
  end

  defp typespec_for_item(items, types_namespace, types) when is_map(items) do
    type_ref = get_value(items, :type_ref) || get_value(items, "type_ref")
    type = get_value(items, :type) || get_value(items, "type")

    cond do
      type_ref -> "#{types_namespace}.#{type_ref}.t()"
      type_defined?(type, types) -> "#{types_namespace}.#{type}.t()"
      true -> Type.map_type_to_typespec(normalize_key(type || "any"))
    end
  end

  defp typespec_for_item(items, types_namespace, types) do
    if type_defined?(items, types) do
      "#{types_namespace}.#{items}.t()"
    else
      Type.map_type_to_typespec(normalize_key(items || "any"))
    end
  end

  defp field_ref_info(field, types, types_namespace) do
    name = field.name
    type_ref = field_type_ref(field)
    type = field_type(field)
    items = field_items(field)

    case ref_kind(type_ref, type, items, types) do
      {:single, ref} -> {name, :single, "#{types_namespace}.#{ref}"}
      {:list, ref} -> {name, :list, "#{types_namespace}.#{ref}"}
      :none -> nil
    end
  end

  defp field_typespec_data(field_def) do
    %{
      type_ref: get_value(field_def, :type_ref) || get_value(field_def, "type_ref"),
      type: normalize_key(get_value(field_def, :type) || get_value(field_def, "type") || "any"),
      items: get_value(field_def, :items) || get_value(field_def, "items"),
      value: get_value(field_def, :value) || get_value(field_def, "value")
    }
  end

  defp field_typespec(%{type_ref: type_ref}, types_namespace, _types) when is_binary(type_ref) do
    "#{types_namespace}.#{type_ref}.t()"
  end

  defp field_typespec(%{type: "array", items: items}, types_namespace, types) do
    "[#{typespec_for_item(items, types_namespace, types)}]"
  end

  defp field_typespec(%{type: "literal", value: value}, _types_namespace, _types) do
    literal_typespec(value)
  end

  defp field_typespec(%{type: type}, types_namespace, types) do
    if type_defined?(type, types) do
      "#{types_namespace}.#{type}.t()"
    else
      Type.map_type_to_typespec(normalize_key(type))
    end
  end

  defp field_type_ref(field) do
    get_value(field.defn, :type_ref) || get_value(field.defn, "type_ref")
  end

  defp field_type(field) do
    normalize_key(get_value(field.defn, :type) || get_value(field.defn, "type") || "")
  end

  defp field_items(field) do
    get_value(field.defn, :items) || get_value(field.defn, "items")
  end

  defp ref_kind(type_ref, _type, _items, _types) when is_binary(type_ref), do: {:single, type_ref}

  defp ref_kind(_type_ref, "array", items, types) do
    case list_item_ref(items, types) do
      nil -> :none
      ref -> {:list, ref}
    end
  end

  defp ref_kind(_type_ref, _type, _items, _types), do: :none

  defp list_item_ref(items, _types) when is_map(items) do
    get_value(items, :type_ref) || get_value(items, "type_ref")
  end

  defp list_item_ref(items, types) when is_binary(items) do
    if type_defined?(items, types), do: items, else: nil
  end

  defp list_item_ref(_items, _types), do: nil

  defp request_fields(%Endpoint{request: nil}, _types), do: []

  defp request_fields(%Endpoint{request: request}, types) do
    case Map.get(types, request) || Map.get(types, normalize_key(request)) do
      %{fields: fields} when is_map(fields) -> normalize_fields(fields)
      %{"fields" => fields} when is_map(fields) -> normalize_fields(fields)
      _ -> []
    end
  end

  defp normalize_fields(fields) do
    fields
    |> Enum.map(fn {name, defn} -> %{name: normalize_key(name), defn: defn} end)
    |> Enum.sort_by(& &1.name)
  end

  defp split_fields(fields, path_params) do
    {literal_fields, fields} = Enum.split_with(fields, &literal_field?/1)

    {required_fields, optional_fields} =
      fields
      |> Enum.reject(fn field -> field.name in path_params end)
      |> Enum.split_with(&required_field?/1)

    {required_fields, optional_fields, literal_fields}
  end

  defp required_field?(%{defn: defn}) do
    get_value(defn, :required) == true || get_value(defn, "required") == true
  end

  defp literal_field?(%{defn: defn}) do
    normalize_key(get_value(defn, :type) || get_value(defn, "type") || "") == "literal" or
      not is_nil(get_value(defn, :value)) or
      not is_nil(get_value(defn, "value"))
  end

  defp extract_path_params(path) do
    Regex.scan(~r/{([^}]+)}|:([A-Za-z0-9_]+)/, path, capture: :all_but_first)
    |> Enum.map(fn captures ->
      Enum.find(captures, fn value -> value not in [nil, ""] end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp field_def_for_param(param, endpoint, types) do
    param = to_string(param)

    fields = request_fields(endpoint, types)

    case Enum.find(fields, fn field -> field.name == param end) do
      nil -> nil
      field -> field.defn
    end
  end

  defp function_name(id, :sync), do: id
  defp function_name(id, :async), do: "#{id}_async"
  defp function_name(id, :stream), do: "#{id}_stream"

  defp base_namespace(module_name, resource) do
    module_part = resource |> String.split("_") |> Enum.map_join(&String.capitalize/1)
    String.replace_suffix(module_name, ".#{module_part}", "")
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, normalize_key(key))
  end

  defp get_value(_map, _key), do: nil

  defp type_defined?(type_name, types) when is_binary(type_name) do
    Map.has_key?(types, type_name) || Map.has_key?(types, normalize_key(type_name))
  end

  defp type_defined?(_type_name, _types), do: false

  defp literal_typespec(value) when is_integer(value), do: "integer()"
  defp literal_typespec(value) when is_float(value), do: "float()"
  defp literal_typespec(value) when is_boolean(value), do: "boolean()"
  defp literal_typespec(value) when is_binary(value), do: "String.t()"
  defp literal_typespec(_value), do: "term()"
end
