defmodule Pristine.OpenAPI do
  @moduledoc """
  Generates OpenAPI 3.1 specifications from Pristine manifests.

  This module converts Pristine manifest definitions into standard OpenAPI format,
  enabling integration with ecosystem tools like Swagger UI, API documentation
  generators, and testing tools.

  ## Usage

      {:ok, spec} = Pristine.OpenAPI.generate(manifest)
      {:ok, json} = Pristine.OpenAPI.generate(manifest, format: :json)
      {:ok, yaml} = Pristine.OpenAPI.generate(manifest, format: :yaml)

  ## Options

    * `:format` - Output format: `:map` (default), `:json`, or `:yaml`

  """

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint
  alias Sinter.Schema, as: SinterSchema

  @openapi_version "3.1.0"

  @type format :: :map | :json | :yaml
  @type option :: {:format, format}

  @default_simple_type_schema %{"type" => "string"}
  @simple_type_schemas %{
    any: %{},
    array: %{"type" => "array", "items" => %{}},
    boolean: %{"type" => "boolean"},
    float: %{"type" => "number"},
    integer: %{"type" => "integer"},
    map: %{"type" => "object"},
    null: %{"type" => "null"},
    number: %{"type" => "number"},
    object: %{"type" => "object"},
    string: %{"type" => "string"}
  }
  @simple_type_aliases Map.new(@simple_type_schemas, fn {type, _schema} ->
                         {Atom.to_string(type), type}
                       end)

  @doc """
  Generates an OpenAPI specification from a Pristine manifest.

  ## Parameters

    * `manifest` - A loaded Pristine manifest
    * `opts` - Generation options

  ## Options

    * `:format` - Output format: `:map` (default), `:json`, or `:yaml`

  ## Returns

    * `{:ok, spec}` where spec is a map, JSON string, or YAML string
    * `{:error, reason}` if generation fails

  ## Examples

      {:ok, spec} = Pristine.OpenAPI.generate(manifest)
      {:ok, json} = Pristine.OpenAPI.generate(manifest, format: :json)

  """
  @spec generate(Manifest.t(), [option]) :: {:ok, map() | String.t()} | {:error, term()}
  def generate(%Manifest{} = manifest, opts \\ []) do
    format = Keyword.get(opts, :format, :map)

    spec = %{
      "openapi" => @openapi_version,
      "info" => build_info(manifest),
      "paths" => build_paths(manifest),
      "components" => build_components(manifest)
    }

    format_output(spec, format)
  end

  @doc """
  Converts a Sinter-style schema definition to OpenAPI JSON Schema format.

  ## Parameters

    * `schema` - A schema map with `:type` and optional constraints

  ## Examples

      iex> Pristine.OpenAPI.schema_to_openapi(%{type: :string})
      %{"type" => "string"}

      iex> Pristine.OpenAPI.schema_to_openapi(%{type: :integer, minimum: 1})
      %{"type" => "integer", "minimum" => 1}

  """
  @spec schema_to_openapi(map() | tuple() | atom() | SinterSchema.t()) :: map()
  def schema_to_openapi(%SinterSchema{} = schema) do
    convert_schema(schema)
  end

  def schema_to_openapi(schema) when is_map(schema) do
    convert_schema(schema)
  end

  def schema_to_openapi(schema) when is_tuple(schema) do
    convert_schema(schema)
  end

  def schema_to_openapi(type) when is_atom(type) do
    convert_simple_type(type)
  end

  # Private functions - Info Section

  defp build_info(%Manifest{} = manifest) do
    %{
      "title" => manifest.name || "API",
      "version" => manifest.version || "1.0.0"
    }
  end

  # Private functions - Paths Section

  defp build_paths(%Manifest{endpoints: endpoints}) when is_map(endpoints) do
    endpoints
    |> Map.values()
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {path, path_endpoints} ->
      {path, build_path_item(path_endpoints)}
    end)
    |> Map.new()
  end

  defp build_paths(%Manifest{endpoints: endpoints}) when is_list(endpoints) do
    endpoints
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {path, path_endpoints} ->
      {path, build_path_item(path_endpoints)}
    end)
    |> Map.new()
  end

  defp build_path_item(endpoints) do
    endpoints
    |> Enum.map(fn endpoint ->
      {method_string(endpoint.method), build_operation(endpoint)}
    end)
    |> Map.new()
  end

  defp build_operation(%Endpoint{} = endpoint) do
    %{
      "operationId" => endpoint.id
    }
    |> maybe_put("summary", endpoint.description)
    |> maybe_put("description", endpoint.description)
    |> maybe_put_list("parameters", build_parameters(endpoint))
    |> maybe_put("requestBody", build_request_body(endpoint))
    |> Map.put("responses", build_responses(endpoint))
  end

  defp build_parameters(%Endpoint{path: path}) do
    path_params = extract_path_params(path)
    build_path_params(path_params)
  end

  defp extract_path_params(path) do
    ~r/\{([^}]+)\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp build_path_params(names) do
    Enum.map(names, fn name ->
      %{
        "name" => name,
        "in" => "path",
        "required" => true,
        "schema" => %{"type" => "string"}
      }
    end)
  end

  defp build_request_body(%Endpoint{request: nil}), do: nil

  defp build_request_body(%Endpoint{request: type_id}) do
    %{
      "required" => true,
      "content" => %{
        "application/json" => %{
          "schema" => %{"$ref" => type_ref(type_id)}
        }
      }
    }
  end

  defp build_responses(%Endpoint{response: nil}) do
    %{"200" => %{"description" => "Success"}}
  end

  defp build_responses(%Endpoint{response: type_id}) do
    %{
      "200" => %{
        "description" => "Success",
        "content" => %{
          "application/json" => %{
            "schema" => %{"$ref" => type_ref(type_id)}
          }
        }
      }
    }
  end

  # Private functions - Components Section

  defp build_components(%Manifest{types: types}) do
    schemas =
      types
      |> Enum.map(fn {type_name, type_def} ->
        {type_name, convert_type_def(type_name, type_def, types)}
      end)
      |> Map.new()

    %{
      "schemas" => schemas
    }
  end

  defp convert_type_def(
         _type_name,
         %{kind: :union, discriminator: discriminator} = type_def,
         _types
       ) do
    mapping = discriminator.mapping || %{}

    %{
      "oneOf" =>
        mapping
        |> Map.values()
        |> Enum.uniq()
        |> Enum.map(&%{"$ref" => type_ref(&1)}),
      "discriminator" => %{
        "propertyName" => discriminator.field,
        "mapping" => Map.new(mapping, fn {value, target} -> {value, type_ref(target)} end)
      }
    }
    |> maybe_put("description", Map.get(type_def, :description))
  end

  defp convert_type_def(_type_name, %{kind: :alias} = type_def, types) do
    type_def
    |> convert_alias_type_def(types)
    |> maybe_put("description", Map.get(type_def, :description))
  end

  defp convert_type_def(_type_name, %{fields: fields} = type_def, types) when is_map(fields) do
    {properties, required} =
      Enum.reduce(fields, {%{}, []}, fn {name, field_def}, {props_acc, req_acc} ->
        field_name = normalize_key(name)
        prop_schema = convert_field_def(field_def, types)
        new_props = Map.put(props_acc, field_name, prop_schema)

        new_req =
          if field_required?(field_def),
            do: [field_name | req_acc],
            else: req_acc

        {new_props, new_req}
      end)

    %{
      "type" => "object",
      "properties" => properties
    }
    |> maybe_put("description", Map.get(type_def, :description))
    |> maybe_put_required(required)
  end

  defp convert_type_def(_type_name, _type_def, _types), do: %{"type" => "object"}

  defp convert_field_def(field_def, types) when is_map(field_def) do
    field_def
    |> convert_type_descriptor(types)
    |> apply_field_constraints(field_def)
    |> maybe_put("description", get_value(field_def, :description))
    |> maybe_put("default", get_value(field_def, :default))
  end

  defp convert_field_def(_field_def, _types), do: %{"type" => "string"}

  defp field_required?(field_def) when is_map(field_def) do
    Map.get(field_def, :required) == true or Map.get(field_def, "required") == true
  end

  defp field_required?(_), do: false

  # Private functions - Schema Conversion

  defp convert_schema(%SinterSchema{} = schema) do
    {properties, required} =
      Enum.reduce(schema.fields, {%{}, []}, fn {name, field}, {props_acc, req_acc} ->
        prop_schema = convert_schema(field.type)
        new_props = Map.put(props_acc, to_string(name), prop_schema)

        new_req =
          if field.required,
            do: [to_string(name) | req_acc],
            else: req_acc

        {new_props, new_req}
      end)

    %{
      "type" => "object",
      "properties" => properties
    }
    |> maybe_put_required(required)
    |> maybe_put("title", schema.config[:title])
    |> maybe_put("description", schema.config[:description])
  end

  defp convert_schema(%{type: :string} = schema) do
    %{"type" => "string"}
    |> maybe_put("format", format_to_string(schema[:format]))
    |> maybe_put("minLength", schema[:min_length])
    |> maybe_put("maxLength", schema[:max_length])
    |> maybe_put("pattern", schema[:pattern])
  end

  defp convert_schema(%{type: :integer} = schema) do
    %{"type" => "integer"}
    |> maybe_put("minimum", schema[:minimum])
    |> maybe_put("maximum", schema[:maximum])
  end

  defp convert_schema(%{type: :number} = schema) do
    %{"type" => "number"}
    |> maybe_put("minimum", schema[:minimum])
    |> maybe_put("maximum", schema[:maximum])
  end

  defp convert_schema(%{type: :boolean}), do: %{"type" => "boolean"}

  defp convert_schema({:object, %SinterSchema{} = schema}) do
    convert_schema(schema)
  end

  defp convert_schema({:array, item_type}) do
    %{
      "type" => "array",
      "items" => convert_schema(item_type)
    }
  end

  defp convert_schema({:literal, value}) do
    %{"const" => value}
  end

  defp convert_schema({:union, types}) do
    %{
      "oneOf" => Enum.map(types, &convert_schema/1)
    }
  end

  defp convert_schema({:discriminated_union, opts}) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    %{
      "oneOf" =>
        Enum.map(variants, fn {_key, schema} ->
          convert_schema(schema)
        end),
      "discriminator" => %{
        "propertyName" => to_string(discriminator)
      }
    }
  end

  defp convert_schema(%{type: {:array, item_type}}) do
    %{
      "type" => "array",
      "items" => convert_schema(%{type: item_type})
    }
  end

  defp convert_schema(%{type: {:literal, value}}) do
    %{"const" => value}
  end

  defp convert_schema(%{type: {:union, types}}) do
    %{
      "oneOf" => Enum.map(types, fn t -> convert_schema(%{type: t}) end)
    }
  end

  defp convert_schema(%{type: {:discriminated_union, opts}}) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    %{
      "oneOf" =>
        Enum.map(variants, fn {_key, schema} ->
          convert_schema(schema)
        end),
      "discriminator" => %{
        "propertyName" => to_string(discriminator),
        "mapping" => build_discriminator_mapping(variants)
      }
    }
  end

  defp convert_schema(%{type: :map, properties: props}) do
    {properties, required} =
      Enum.reduce(props, {%{}, []}, fn {name, type, opts}, {props_acc, req_acc} ->
        prop_schema = convert_schema(%{type: type})
        new_props = Map.put(props_acc, to_string(name), prop_schema)

        new_req =
          if Keyword.get(opts, :required, false),
            do: [to_string(name) | req_acc],
            else: req_acc

        {new_props, new_req}
      end)

    result = %{
      "type" => "object",
      "properties" => properties
    }

    if Enum.empty?(required),
      do: result,
      else: Map.put(result, "required", Enum.reverse(required))
  end

  defp convert_schema(%{type: type}) when is_atom(type) do
    convert_simple_type(type)
  end

  defp convert_schema(_), do: %{"type" => "string"}

  defp convert_simple_type(type) do
    type
    |> normalize_simple_type()
    |> simple_type_schema()
  end

  # Private functions - Helpers

  defp convert_alias_type_def(type_def, types) do
    cond do
      type_ref = get_value(type_def, :type_ref) ->
        %{"$ref" => type_ref(type_ref)}

      is_list(get_value(type_def, :choices)) ->
        get_value(type_def, :choices)
        |> enum_schema()

      not is_nil(get_value(type_def, :value)) ->
        %{"const" => get_value(type_def, :value)}

      normalize_key(get_value(type_def, :type) || "") == "array" ->
        %{
          "type" => "array",
          "items" => convert_items_descriptor(get_value(type_def, :items), types)
        }

      type = get_value(type_def, :type) ->
        convert_simple_type(type)

      true ->
        %{"type" => "object"}
    end
  end

  defp convert_type_descriptor(definition, types) do
    cond do
      type_ref = get_value(definition, :type_ref) ->
        %{"$ref" => type_ref(type_ref)}

      normalize_key(get_value(definition, :type) || "") == "array" ->
        %{
          "type" => "array",
          "items" => convert_items_descriptor(get_value(definition, :items), types)
        }

      literal_type?(definition) ->
        %{"const" => get_value(definition, :value)}

      type = get_value(definition, :type) ->
        convert_simple_type(type)

      true ->
        %{"type" => "string"}
    end
  end

  defp convert_items_descriptor(items, types) when is_map(items) do
    convert_type_descriptor(items, types)
  end

  defp convert_items_descriptor(items, types) when is_binary(items) or is_atom(items) do
    normalized = normalize_key(items)

    if Map.has_key?(types, normalized) do
      %{"$ref" => type_ref(normalized)}
    else
      convert_simple_type(items)
    end
  end

  defp convert_items_descriptor(_items, _types), do: %{}

  defp apply_field_constraints(schema, field_def) do
    schema
    |> maybe_put("enum", get_value(field_def, :choices))
    |> maybe_put("minLength", get_value(field_def, :min_length))
    |> maybe_put("maxLength", get_value(field_def, :max_length))
    |> maybe_put("minItems", get_value(field_def, :min_items))
    |> maybe_put("maxItems", get_value(field_def, :max_items))
    |> maybe_put("minimum", get_value(field_def, :gteq))
    |> maybe_put("exclusiveMinimum", get_value(field_def, :gt))
    |> maybe_put("maximum", get_value(field_def, :lteq))
    |> maybe_put("exclusiveMaximum", get_value(field_def, :lt))
    |> maybe_put("format", format_to_string(get_value(field_def, :format)))
  end

  defp enum_schema(values) when is_list(values) do
    inferred_type =
      case Enum.uniq_by(values, &value_kind/1) do
        [value] -> enum_value_type(value)
        _ -> nil
      end

    %{}
    |> maybe_put("type", inferred_type)
    |> Map.put("enum", values)
  end

  defp maybe_put_required(map, []), do: map
  defp maybe_put_required(map, required), do: Map.put(map, "required", Enum.reverse(required))

  defp build_discriminator_mapping(variants) do
    variants
    |> Enum.map(fn {key, _schema} ->
      {to_string(key), "#/components/schemas/#{key}"}
    end)
    |> Map.new()
  end

  defp type_ref(type_id), do: "#/components/schemas/#{type_id}"

  defp method_string(method) when is_binary(method) do
    method |> String.downcase()
  end

  defp method_string(method) when is_atom(method) do
    method |> Atom.to_string() |> String.downcase()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, normalize_key(key))
  end

  defp normalize_simple_type(type) when is_atom(type), do: type
  defp normalize_simple_type(type) when is_binary(type), do: Map.get(@simple_type_aliases, type)
  defp normalize_simple_type(_type), do: nil

  defp simple_type_schema(type),
    do: Map.get(@simple_type_schemas, type, @default_simple_type_schema)

  defp literal_type?(definition) when is_map(definition) do
    normalize_key(get_value(definition, :type) || "") == "literal" or
      not is_nil(get_value(definition, :value))
  end

  defp value_kind(value) when is_binary(value), do: :string
  defp value_kind(value) when is_integer(value), do: :integer
  defp value_kind(value) when is_float(value), do: :number
  defp value_kind(value) when is_boolean(value), do: :boolean
  defp value_kind(_value), do: :mixed

  defp enum_value_type(value) do
    case value_kind(value) do
      :string -> "string"
      :integer -> "integer"
      :number -> "number"
      :boolean -> "boolean"
      _ -> nil
    end
  end

  defp format_to_string(nil), do: nil
  defp format_to_string(format) when is_atom(format), do: Atom.to_string(format)
  defp format_to_string(format) when is_binary(format), do: format

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, key, list), do: Map.put(map, key, list)

  # Private functions - Output Formatting

  defp format_output(spec, :map), do: {:ok, spec}
  defp format_output(spec, :json), do: {:ok, Jason.encode!(spec, pretty: true)}

  defp format_output(spec, :yaml) do
    yaml = to_yaml(spec, 0)
    {:ok, yaml}
  end

  # Simple YAML encoder
  defp to_yaml(map, indent) when is_map(map) do
    Enum.map_join(map, "\n", fn {k, v} ->
      prefix = String.duplicate("  ", indent)
      "#{prefix}#{k}:#{to_yaml_value(v, indent)}"
    end)
  end

  defp to_yaml_value(nil, _), do: " null"
  defp to_yaml_value(true, _), do: " true"
  defp to_yaml_value(false, _), do: " false"
  defp to_yaml_value(s, _) when is_binary(s), do: " #{inspect(s)}"
  defp to_yaml_value(n, _) when is_number(n), do: " #{n}"

  defp to_yaml_value(list, indent) when is_list(list) do
    if Enum.empty?(list) do
      " []"
    else
      items =
        Enum.map(list, fn item ->
          prefix = String.duplicate("  ", indent + 1)
          "#{prefix}-#{to_yaml_inline(item, indent + 1)}"
        end)

      "\n" <> Enum.join(items, "\n")
    end
  end

  defp to_yaml_value(map, indent) when is_map(map) do
    if map_size(map) == 0 do
      " {}"
    else
      "\n" <> to_yaml(map, indent + 1)
    end
  end

  defp to_yaml_inline(value, _indent) when is_binary(value), do: " #{inspect(value)}"
  defp to_yaml_inline(value, _indent) when is_number(value), do: " #{value}"
  defp to_yaml_inline(value, _indent) when is_boolean(value), do: " #{value}"
  defp to_yaml_inline(nil, _indent), do: " null"

  defp to_yaml_inline(map, indent) when is_map(map) do
    "\n" <> to_yaml(map, indent + 1)
  end

  defp to_yaml_inline(list, indent) when is_list(list) do
    to_yaml_value(list, indent)
  end
end
