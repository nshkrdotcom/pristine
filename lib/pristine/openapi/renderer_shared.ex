defmodule Pristine.OpenAPI.RendererShared do
  @moduledoc false
  @compile {:no_warn_undefined, [OpenAPI.Processor.Schema, OpenAPI.Renderer.Util]}

  @multipart_content_type "multipart/form-data"

  alias OpenAPI.Processor.Schema, as: ProcessedSchema
  alias OpenAPI.Renderer.Util, as: RendererUtil

  defguardp is_schema_reference(ref)
            when Kernel.is_reference(ref) or
                   (is_tuple(ref) and tuple_size(ref) == 2 and elem(ref, 0) == :ref)

  def request_partition_spec(state, operation) when is_map(state) and is_map(operation) do
    request_body = Map.get(operation, :request_body, [])
    path_params = Map.get(operation, :request_path_parameters, [])
    query_params = Map.get(operation, :request_query_parameters, [])

    {multipart_request_body, standard_request_body} =
      Enum.split_with(request_body, fn {content_type, _type} ->
        String.starts_with?(content_type, @multipart_content_type)
      end)

    %{
      auth: {"auth", :auth},
      path: key_specs(path_params),
      query: key_specs(query_params),
      body: payload_spec(state, standard_request_body, {"body", :body}),
      form_data: payload_spec(state, multipart_request_body, {"form_data", :form_data})
    }
  end

  def render_request_info(state, request_body, format) do
    render_request_info(state, request_body, format, &default_readable_type/2)
  end

  def render_request_info(_state, [], _format, _readable_type), do: nil

  def render_request_info(state, request_body, :map, readable_type) do
    items =
      Map.new(request_body, fn {content_type, type} ->
        {content_type, readable_type.(state, type)}
      end)

    quote do
      {:request, unquote(Macro.escape(items))}
    end
  end

  def render_request_info(state, request_body, _format, readable_type) do
    items =
      Enum.map(request_body, fn {content_type, type} ->
        readable = readable_type.(state, type)

        quote do
          {unquote(content_type), unquote(readable)}
        end
      end)

    quote do
      {:request, unquote(items)}
    end
  end

  def render_response_info(state, responses) do
    render_response_info(state, responses, &default_readable_type/2)
  end

  def render_response_info(_state, [], _readable_type), do: nil

  def render_response_info(state, responses, readable_type) do
    items =
      responses
      |> Enum.sort_by(fn {status_or_default, _schemas} -> status_or_default end)
      |> Enum.map(fn {status_or_default, schemas} ->
        readable = readable_type.(state, {:union, Map.values(schemas)})

        quote do
          {unquote(status_or_default), unquote(readable)}
        end
      end)

    quote do
      {:response, unquote(items)}
    end
  end

  def render_security_info(operation, config) when is_map(operation) and is_list(config) do
    security = security_requirements(operation, config)

    case security do
      nil -> nil
      security -> quote(do: {:security, unquote(Macro.escape(security))})
    end
  end

  def security_requirements(operation, config) when is_map(operation) and is_list(config) do
    Map.get(operation, :security)
    |> normalize_security_requirements()
  end

  def merge_schema_groups(schemas, schemas_by_ref) do
    schemas
    |> Enum.group_by(&{Map.get(&1, :module_name), Map.get(&1, :type_name)})
    |> Enum.map(fn {_module_and_type, grouped} ->
      merge_schema_group(grouped, schemas_by_ref)
    end)
    |> List.flatten()
    |> Enum.sort_by(&Map.get(&1, :type_name))
  end

  def merge_schema_group(grouped, schemas_by_ref) do
    grouped
    |> Enum.sort_by(&stable_schema_term(&1, schemas_by_ref))
    |> Enum.reduce(&merge_processed_schemas/2)
  end

  defp payload_spec(_state, [], _fallback_key), do: %{mode: :none}

  defp payload_spec(state, request_body, fallback_key) do
    keys =
      request_body
      |> Enum.reduce(MapSet.new(), fn {_content_type, type}, names ->
        MapSet.union(names, request_field_names(state, type))
      end)
      |> MapSet.to_list()
      |> Enum.sort()

    if keys == [] do
      %{mode: :key, key: fallback_key}
    else
      %{mode: :keys, keys: Enum.map(keys, &{&1, String.to_atom(&1)})}
    end
  end

  defp key_specs(params) do
    Enum.map(params, fn param ->
      name = Map.get(param, :name)
      {name, String.to_atom(name)}
    end)
  end

  defp request_field_names(state, {:union, types}) do
    Enum.reduce(types, MapSet.new(), fn type, names ->
      MapSet.union(names, request_field_names(state, type))
    end)
  end

  defp request_field_names(state, ref) when is_schema_reference(ref) do
    schemas = Map.get(state, :schemas, %{})

    case Map.get(schemas, ref) do
      %{fields: fields} ->
        Enum.reduce(fields, MapSet.new(), fn field, names ->
          MapSet.put(names, Map.get(field, :name))
        end)

      nil ->
        MapSet.new()
    end
  end

  defp request_field_names(_state, _type), do: MapSet.new()

  defp normalize_security_requirements(nil), do: nil
  defp normalize_security_requirements(security) when is_list(security), do: Enum.uniq(security)
  defp normalize_security_requirements(security), do: security

  defp stable_schema_term(schema, schemas_by_ref) do
    [
      module_name: stable_module_name(Map.get(schema, :module_name)),
      type_name: stable_atom(Map.get(schema, :type_name)),
      output_format: stable_atom(Map.get(schema, :output_format)),
      title: Map.get(schema, :title),
      description: Map.get(schema, :description),
      context:
        schema
        |> Map.get(:context, [])
        |> Enum.map(&stable_term(&1, schemas_by_ref))
        |> Enum.sort(),
      fields:
        schema
        |> Map.get(:fields, [])
        |> Enum.map(&stable_field_term(&1, schemas_by_ref))
        |> Enum.sort()
    ]
  end

  defp stable_field_term(field, schemas_by_ref) do
    [
      name: Map.get(field, :name),
      type: stable_term(Map.get(field, :type), schemas_by_ref),
      required: Map.get(field, :required),
      nullable: Map.get(field, :nullable),
      private: Map.get(field, :private),
      read_only: Map.get(field, :read_only),
      write_only: Map.get(field, :write_only)
    ]
  end

  defp stable_term(reference, schemas_by_ref) when is_schema_reference(reference) do
    case Map.get(schemas_by_ref, reference) do
      nil ->
        {:schema_ref, "missing"}

      schema ->
        {:schema_ref, shallow_schema_term(schema)}
    end
  end

  defp stable_term(%_{} = struct, schemas_by_ref) do
    struct
    |> Map.from_struct()
    |> stable_term(schemas_by_ref)
  end

  defp stable_term(map, schemas_by_ref) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {stable_term(key, schemas_by_ref), stable_term(value, schemas_by_ref)}
    end)
    |> Enum.sort()
  end

  defp stable_term(tuple, schemas_by_ref) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&stable_term(&1, schemas_by_ref))
    |> List.to_tuple()
  end

  defp stable_term(list, schemas_by_ref) when is_list(list),
    do: Enum.map(list, &stable_term(&1, schemas_by_ref))

  defp stable_term(atom, _schemas_by_ref) when is_atom(atom), do: Atom.to_string(atom)
  defp stable_term(value, _schemas_by_ref), do: value

  defp shallow_schema_term(schema) do
    [
      module_name: stable_module_name(Map.get(schema, :module_name)),
      type_name: stable_atom(Map.get(schema, :type_name)),
      output_format: stable_atom(Map.get(schema, :output_format)),
      title: Map.get(schema, :title),
      description: Map.get(schema, :description),
      field_names:
        schema
        |> Map.get(:fields, [])
        |> Enum.map(&Map.get(&1, :name))
        |> Enum.sort()
    ]
  end

  defp stable_module_name(nil), do: nil
  defp stable_module_name(module_name) when is_atom(module_name), do: inspect(module_name)

  defp stable_atom(nil), do: nil
  defp stable_atom(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp merge_processed_schemas(left, right) do
    ProcessedSchema.merge(left, right)
  end

  defp default_readable_type(state, type) do
    RendererUtil.to_readable_type(state, type)
  end
end
