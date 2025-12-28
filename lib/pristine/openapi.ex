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

  @openapi_version "3.1.0"

  @type format :: :map | :json | :yaml
  @type option :: {:format, format}

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
  @spec schema_to_openapi(map() | atom()) :: map()
  def schema_to_openapi(schema) when is_map(schema) do
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
        {type_name, convert_type_def(type_def)}
      end)
      |> Map.new()

    %{
      "schemas" => schemas
    }
  end

  defp convert_type_def(%{fields: fields}) when is_map(fields) do
    {properties, required} =
      Enum.reduce(fields, {%{}, []}, fn {name, field_def}, {props_acc, req_acc} ->
        field_name = normalize_key(name)
        prop_schema = convert_field_def(field_def)
        new_props = Map.put(props_acc, field_name, prop_schema)

        new_req =
          if field_required?(field_def),
            do: [field_name | req_acc],
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

  defp convert_type_def(_), do: %{"type" => "object"}

  defp convert_field_def(field_def) when is_map(field_def) do
    type = Map.get(field_def, :type) || Map.get(field_def, "type") || "string"
    convert_simple_type(type)
  end

  defp convert_field_def(_), do: %{"type" => "string"}

  defp field_required?(field_def) when is_map(field_def) do
    Map.get(field_def, :required) == true or Map.get(field_def, "required") == true
  end

  defp field_required?(_), do: false

  # Private functions - Schema Conversion

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

  defp convert_simple_type(:string), do: %{"type" => "string"}
  defp convert_simple_type(:integer), do: %{"type" => "integer"}
  defp convert_simple_type(:number), do: %{"type" => "number"}
  defp convert_simple_type(:boolean), do: %{"type" => "boolean"}
  defp convert_simple_type(:any), do: %{}
  defp convert_simple_type(:null), do: %{"type" => "null"}

  defp convert_simple_type(type) when is_binary(type) do
    case type do
      "string" -> %{"type" => "string"}
      "integer" -> %{"type" => "integer"}
      "number" -> %{"type" => "number"}
      "boolean" -> %{"type" => "boolean"}
      _ -> %{"type" => "string"}
    end
  end

  defp convert_simple_type(_), do: %{"type" => "string"}

  defp build_discriminator_mapping(variants) do
    variants
    |> Enum.map(fn {key, _schema} ->
      {to_string(key), "#/components/schemas/#{key}"}
    end)
    |> Map.new()
  end

  # Private functions - Helpers

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
