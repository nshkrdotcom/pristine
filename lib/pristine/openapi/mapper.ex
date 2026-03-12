defmodule Pristine.OpenAPI.Mapper do
  @moduledoc """
  Maps raw OpenAPI generator state into Pristine's canonical IR.
  """

  alias Pristine.OpenAPI.IR
  alias Pristine.OpenAPI.IR.CodeSample
  alias Pristine.OpenAPI.IR.Field
  alias Pristine.OpenAPI.IR.Operation
  alias Pristine.OpenAPI.IR.Schema
  alias Pristine.OpenAPI.IR.SecurityScheme
  alias Pristine.OpenAPI.IR.SourceContext

  @http_methods ~w(get put post delete options head patch trace)a

  @spec to_ir(map(), keyword()) :: IR.t()
  def to_ir(generator_state, opts \\ []) when is_map(generator_state) and is_list(opts) do
    source_contexts = normalize_source_contexts(Keyword.get(opts, :source_contexts, %{}))

    struct(IR,
      operations: map_operations(Map.get(generator_state, :operations, []), source_contexts),
      schemas: map_schemas(Map.get(generator_state, :schemas, %{})),
      security_schemes: map_security_schemes(generator_state),
      source_contexts: map_source_contexts(source_contexts)
    )
  end

  @spec normalize_source_contexts(term()) :: %{optional({atom(), String.t()}) => term()}
  def normalize_source_contexts(source_contexts) when is_map(source_contexts) do
    Enum.reduce(source_contexts, %{}, fn
      {{method, path}, context}, acc when is_binary(path) ->
        case normalize_method(method) do
          nil -> acc
          normalized_method -> Map.put(acc, {normalized_method, path}, context)
        end

      _entry, acc ->
        acc
    end)
  end

  def normalize_source_contexts(source_contexts) when is_list(source_contexts) do
    source_contexts
    |> Map.new()
    |> normalize_source_contexts()
  end

  def normalize_source_contexts(_source_contexts), do: %{}

  defp map_operations(operations, source_contexts) do
    operations
    |> Enum.map(&map_operation(&1, source_contexts))
    |> Enum.sort_by(fn operation ->
      {inspect(operation.module_name), Atom.to_string(operation.function_name), operation.path}
    end)
  end

  defp map_operation(operation, source_contexts) do
    method = Map.get(operation, :request_method)
    path = Map.get(operation, :request_path)
    source_context = Map.get(source_contexts, {method, path})

    struct(Operation,
      module_name: Map.get(operation, :module_name),
      function_name: Map.get(operation, :function_name),
      method: method,
      path: path,
      summary: Map.get(operation, :summary),
      description: Map.get(operation, :description),
      deprecated: Map.get(operation, :deprecated, false),
      external_docs: normalize_external_docs(Map.get(operation, :external_docs)),
      tags: Map.get(operation, :tags, []),
      security: normalize_security_requirements(Map.get(operation, :security)),
      request_body: normalize_request_body_docs(Map.get(operation, :request_body_docs)),
      query_params: Enum.map(Map.get(operation, :request_query_parameters, []), &map_param/1),
      path_params: Enum.map(Map.get(operation, :request_path_parameters, []), &map_param/1),
      header_params: Enum.map(Map.get(operation, :request_header_parameters, []), &map_param/1),
      response_docs: Enum.map(Map.get(operation, :response_docs, []), &normalize_response_doc/1),
      extensions: normalize_map(Map.get(operation, :extensions, %{})),
      source_context: map_source_context({method, path}, source_context),
      code_samples: map_code_samples(source_context)
    )
  end

  defp map_param(param) do
    %{
      name: Map.get(param, :name),
      location: Map.get(param, :location),
      description: Map.get(param, :description),
      required: Map.get(param, :required, false),
      deprecated: Map.get(param, :deprecated, false),
      example: Map.get(param, :example),
      examples: normalize_value(Map.get(param, :examples)),
      style: Map.get(param, :style),
      explode: Map.get(param, :explode, false),
      value_type: Map.get(param, :value_type),
      extensions: normalize_map(Map.get(param, :extensions, %{}))
    }
  end

  defp normalize_request_body_docs(nil), do: nil

  defp normalize_request_body_docs(docs) do
    %{
      description: Map.get(docs, :description),
      required: Map.get(docs, :required, false),
      content_types: Map.get(docs, :content_types, [])
    }
  end

  defp normalize_response_doc(response_doc) do
    %{
      status: Map.get(response_doc, :status),
      description: Map.get(response_doc, :description),
      content_types: Map.get(response_doc, :content_types, [])
    }
  end

  defp map_schemas(schemas) do
    schemas
    |> Enum.map(fn {ref, schema} -> map_schema(ref, schema) end)
    |> Enum.sort_by(fn schema ->
      {inspect(schema.module_name), Atom.to_string(schema.type_name)}
    end)
  end

  defp map_schema(ref, schema) do
    struct(Schema,
      ref: ref,
      module_name: Map.get(schema, :module_name),
      type_name: Map.get(schema, :type_name),
      title: Map.get(schema, :title),
      description: Map.get(schema, :description),
      deprecated: Map.get(schema, :deprecated, false),
      example: Map.get(schema, :example),
      examples: normalize_value(Map.get(schema, :examples)),
      external_docs: normalize_external_docs(Map.get(schema, :external_docs)),
      extensions: normalize_map(Map.get(schema, :extensions, %{})),
      output_format: Map.get(schema, :output_format),
      contexts: Map.get(schema, :context, []),
      fields: Enum.map(Map.get(schema, :fields, []), &map_field/1)
    )
  end

  defp map_field(field) do
    struct(Field,
      name: Map.get(field, :name),
      type: Map.get(field, :type),
      description: Map.get(field, :description),
      default: Map.get(field, :default),
      required: Map.get(field, :required, false),
      nullable: Map.get(field, :nullable, false),
      deprecated: Map.get(field, :deprecated, false),
      read_only: Map.get(field, :read_only, false),
      write_only: Map.get(field, :write_only, false),
      example: Map.get(field, :example),
      examples: normalize_value(Map.get(field, :examples)),
      external_docs: normalize_external_docs(Map.get(field, :external_docs)),
      extensions: normalize_map(Map.get(field, :extensions, %{}))
    )
  end

  defp map_security_schemes(generator_state) do
    generator_state
    |> Map.get(:spec, %{})
    |> Map.get(:components, %{})
    |> Map.get(:security_schemes, %{})
    |> Enum.map(fn {name, scheme} -> {name, map_security_scheme(name, scheme)} end)
    |> Map.new()
  end

  defp map_security_scheme(name, scheme) when is_map(scheme) do
    struct(SecurityScheme,
      name: name,
      type: Map.get(scheme, "type") || Map.get(scheme, :type),
      scheme: Map.get(scheme, "scheme") || Map.get(scheme, :scheme),
      description: Map.get(scheme, "description") || Map.get(scheme, :description),
      details: normalize_map(scheme)
    )
  end

  defp map_security_scheme(name, scheme) do
    struct(SecurityScheme,
      name: name,
      type: nil,
      scheme: nil,
      description: nil,
      details: normalize_value(scheme)
    )
  end

  defp map_source_contexts(source_contexts) do
    Enum.reduce(source_contexts, %{}, fn {key, context}, acc ->
      case map_source_context(key, context) do
        nil -> acc
        mapped_context -> Map.put(acc, key, mapped_context)
      end
    end)
  end

  defp map_source_context(_key, nil), do: nil

  defp map_source_context({_method, _path}, source_context)
       when is_struct(source_context, SourceContext),
       do: source_context

  defp map_source_context({method, path}, context) when is_map(context) do
    struct(SourceContext,
      method: method,
      path: path,
      title: Map.get(context, :title) || Map.get(context, "title"),
      summary: Map.get(context, :summary) || Map.get(context, "summary"),
      description: Map.get(context, :description) || Map.get(context, "description"),
      url:
        Map.get(context, :url) || Map.get(context, "url") || Map.get(context, :source_url) ||
          Map.get(context, "source_url"),
      code_samples: map_code_samples(context),
      metadata: normalize_source_context_metadata(context)
    )
  end

  defp map_source_context({method, path}, context) do
    struct(SourceContext,
      method: method,
      path: path,
      title: nil,
      summary: nil,
      description: inspect(context),
      url: nil,
      code_samples: [],
      metadata: %{}
    )
  end

  defp normalize_source_context_metadata(context) do
    context
    |> Map.drop([:title, "title", :summary, "summary", :description, "description", :url, "url"])
    |> Map.drop([:source_url, "source_url", :code_samples, "code_samples"])
    |> normalize_map()
  end

  defp map_code_samples(nil), do: []

  defp map_code_samples(source_context)
       when is_struct(source_context, SourceContext),
       do: Map.get(source_context, :code_samples, [])

  defp map_code_samples(context) when is_map(context) do
    context
    |> Map.get(:code_samples, Map.get(context, "code_samples", []))
    |> normalize_code_samples()
  end

  defp map_code_samples(code_samples), do: normalize_code_samples(code_samples)

  defp normalize_code_samples(code_samples) when is_list(code_samples) do
    Enum.map(code_samples, &normalize_code_sample/1)
  end

  defp normalize_code_samples(_code_samples), do: []

  defp normalize_code_sample(code_sample)
       when is_struct(code_sample, CodeSample),
       do: code_sample

  defp normalize_code_sample(code_sample) when is_map(code_sample) do
    struct(CodeSample,
      language:
        Map.get(code_sample, :language) || Map.get(code_sample, "language") ||
          Map.get(code_sample, :lang) || Map.get(code_sample, "lang"),
      label: Map.get(code_sample, :label) || Map.get(code_sample, "label"),
      source:
        Map.get(code_sample, :source) || Map.get(code_sample, "source") ||
          Map.get(code_sample, :content) || Map.get(code_sample, "content"),
      metadata:
        code_sample
        |> Map.drop([:language, "language", :lang, "lang", :label, "label", :source, "source"])
        |> Map.drop([:content, "content"])
        |> normalize_map()
    )
  end

  defp normalize_code_sample(code_sample) do
    struct(CodeSample, language: nil, label: nil, source: inspect(code_sample), metadata: %{})
  end

  defp normalize_external_docs(nil), do: nil

  defp normalize_external_docs(external_docs) when is_map(external_docs) do
    %{
      description: Map.get(external_docs, :description) || Map.get(external_docs, "description"),
      url: Map.get(external_docs, :url) || Map.get(external_docs, "url")
    }
  end

  defp normalize_external_docs(external_docs),
    do: %{description: nil, url: inspect(external_docs)}

  defp normalize_map(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_map(other), do: normalize_value(other)

  defp normalize_value(%_{} = struct), do: struct |> Map.from_struct() |> normalize_map()
  defp normalize_value(reference) when is_reference(reference), do: %{reference: reference}

  defp normalize_value(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_value/1)
  end

  defp normalize_value(map) when is_map(map), do: normalize_map(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_security_requirements(nil), do: nil
  defp normalize_security_requirements(security) when is_list(security), do: Enum.uniq(security)
  defp normalize_security_requirements(security), do: security

  defp normalize_method(method) when method in @http_methods, do: method

  defp normalize_method(method) when is_binary(method) do
    method
    |> String.downcase()
    |> case do
      "get" -> :get
      "put" -> :put
      "post" -> :post
      "delete" -> :delete
      "options" -> :options
      "head" -> :head
      "patch" -> :patch
      "trace" -> :trace
      _other -> nil
    end
  end

  defp normalize_method(_method), do: nil
end
