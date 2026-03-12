defmodule Pristine.OpenAPI.DocComposer do
  @moduledoc """
  Shared documentation composition rules for renderer callbacks and docs artifacts.
  """

  alias Pristine.OpenAPI.IR.SourceContext

  @spec operation(map(), keyword()) :: map()
  def operation(operation, opts \\ []) when is_map(operation) and is_list(opts) do
    source_context = resolve_source_context(operation, opts)
    security = Map.get(operation, :security)
    response_docs = operation_response_docs(operation)

    query_params =
      Map.get(operation, :query_params, Map.get(operation, :request_query_parameters, []))

    request_body = Map.get(operation, :request_body_docs, Map.get(operation, :request_body))

    code_samples =
      normalize_code_samples(
        Map.get(operation, :code_samples, source_context_code_samples(source_context))
      )

    sections =
      [
        operation_summary(operation, source_context),
        present(Map.get(operation, :description)),
        render_source_context(source_context),
        render_query_params(query_params),
        render_request_body(request_body),
        render_responses(response_docs),
        render_security(security),
        render_resources(Map.get(operation, :external_docs), source_context),
        render_code_samples(code_samples)
      ]
      |> Enum.reject(&blank?/1)

    %{
      summary: operation_summary(operation, source_context),
      description: Map.get(operation, :description),
      security: security,
      external_docs: normalize_external_docs(Map.get(operation, :external_docs)),
      source_context: normalize_source_context(source_context),
      code_samples: code_samples,
      request_body: normalize_request_body(request_body),
      responses: normalize_responses(response_docs),
      query_params: normalize_params(query_params),
      doc: finalize_doc(Enum.join(sections, "\n\n"))
    }
  end

  @spec operation_doc(map(), keyword()) :: String.t()
  def operation_doc(operation, opts \\ []) do
    operation(operation, opts).doc
  end

  @spec module(map(), keyword()) :: map()
  def module(file, opts \\ []) when is_map(file) and is_list(opts) do
    operations = Map.get(file, :operations, [])
    schemas = Map.get(file, :schemas, [])

    module_doc =
      if operations == [] do
        compose_schema_module_doc(file, schemas)
      else
        compose_operation_module_doc(file, operations, opts)
      end

    %{
      module: Map.get(file, :module),
      operations: Enum.map(operations, &Map.get(&1, :function_name)),
      schema_types: Enum.map(schemas, &Map.get(&1, :type_name)),
      doc: finalize_doc(module_doc)
    }
  end

  @spec module_doc(map(), keyword()) :: String.t()
  def module_doc(file, opts \\ []) do
    module(file, opts).doc
  end

  @spec schema(map()) :: map()
  def schema(schema) when is_map(schema) do
    fields =
      schema
      |> Map.get(:fields, [])
      |> Enum.map(&field(&1, json_friendly_type(Map.get(&1, :type))))

    title = schema_title(schema)

    sections =
      [
        title,
        present(Map.get(schema, :description)),
        render_schema_fields(fields),
        render_resources(Map.get(schema, :external_docs), nil)
      ]
      |> Enum.reject(&blank?/1)

    %{
      title: title,
      description: Map.get(schema, :description),
      fields: fields,
      doc: finalize_doc(Enum.join(sections, "\n\n"))
    }
  end

  @spec field(map(), term()) :: map()
  def field(field, rendered_type) when is_map(field) do
    %{
      default: Map.get(field, :default),
      description: Map.get(field, :description),
      deprecated: Map.get(field, :deprecated, false),
      example: normalize_value(Map.get(field, :example)),
      examples: normalize_value(Map.get(field, :examples)),
      external_docs: normalize_external_docs(Map.get(field, :external_docs)),
      extensions: normalize_map(Map.get(field, :extensions, %{})),
      name: Map.get(field, :name),
      nullable: Map.get(field, :nullable, false),
      read_only: Map.get(field, :read_only, false),
      required: Map.get(field, :required, false),
      type: rendered_type,
      write_only: Map.get(field, :write_only, false)
    }
  end

  @spec json_friendly_type(term()) :: term()
  def json_friendly_type({module, type}) when is_atom(module) and is_atom(type) do
    %{
      module: Atom.to_string(module),
      type: Atom.to_string(type)
    }
  end

  def json_friendly_type(reference) when is_reference(reference) do
    %{reference: inspect(reference)}
  end

  def json_friendly_type({:union, types}) when is_list(types) do
    %{union: Enum.map(types, &json_friendly_type/1)}
  end

  def json_friendly_type({:array, type}) do
    %{array: json_friendly_type(type)}
  end

  def json_friendly_type({tag, value}) when is_atom(tag) do
    %{Atom.to_string(tag) => json_friendly_type(value)}
  end

  def json_friendly_type(list) when is_list(list) do
    Enum.map(list, &json_friendly_type/1)
  end

  def json_friendly_type(atom) when is_atom(atom), do: Atom.to_string(atom)
  def json_friendly_type(tuple) when is_tuple(tuple), do: inspect(tuple)
  def json_friendly_type(map) when is_map(map), do: normalize_map(map)
  def json_friendly_type(value), do: value

  defp compose_operation_module_doc(file, operations, opts) do
    topic =
      file
      |> Map.get(:module)
      |> inspect()
      |> Macro.underscore()
      |> String.replace("_", " ")

    operation_summaries =
      operations
      |> Enum.map(&operation(&1, opts))
      |> Enum.map_join("\n", fn composed ->
        "  * #{composed.summary}"
      end)

    """
    Provides API #{plural(operations, "endpoint")} related to #{topic}

    ## Operations

    #{operation_summaries}
    """
    |> String.trim()
  end

  defp compose_schema_module_doc(file, schemas) do
    module = Map.get(file, :module)

    schema_titles =
      schemas
      |> Enum.map(&schema_title/1)
      |> Enum.uniq()
      |> Enum.map_join("\n", fn title -> "  * #{title}" end)

    base =
      "Provides struct and #{plural(schemas, "type")} for #{inspect(module)}"

    if blank?(schema_titles) do
      base
    else
      """
      #{base}

      ## Types

      #{schema_titles}
      """
      |> String.trim()
    end
  end

  defp render_query_params([]), do: nil

  defp render_query_params(query_params) do
    items =
      query_params
      |> normalize_params()
      |> Enum.map_join("\n", fn param ->
        suffix =
          case present(param.description) do
            nil -> ""
            description -> ": #{description}"
          end

        "  * `#{param.name}`#{suffix}"
      end)

    """
    ## Options

    #{items}
    """
    |> String.trim()
  end

  defp render_request_body(nil), do: nil

  defp render_request_body(request_body) do
    case normalize_request_body(request_body) do
      nil ->
        nil

      request_body ->
        content_types = request_body.content_types |> Enum.map_join(", ", &"`#{&1}`")

        description =
          case present(request_body.description) do
            nil -> nil
            description -> description
          end

        [
          "## Request Body",
          "",
          "**Content Types**: #{content_types}",
          description
        ]
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n")
    end
  end

  defp render_responses([]), do: nil

  defp render_responses(response_docs) do
    items =
      response_docs
      |> normalize_responses()
      |> Enum.map_join("\n", fn response ->
        content_types =
          case response.content_types do
            [] -> nil
            content_types -> " (#{Enum.join(content_types, ", ")})"
          end

        case present(response.description) do
          nil ->
            "  * `#{render_status(response.status)}`#{content_types || ""}"

          description ->
            "  * `#{render_status(response.status)}`#{content_types || ""}: #{description}"
        end
      end)

    """
    ## Responses

    #{items}
    """
    |> String.trim()
  end

  defp render_security(nil), do: nil

  defp render_security([]) do
    """
    ## Security

    Unauthenticated.
    """
    |> String.trim()
  end

  defp render_security(security) do
    items =
      security
      |> Enum.map_join("\n", fn requirement ->
        "  * #{render_security_requirement(requirement)}"
      end)

    """
    ## Security

    #{items}
    """
    |> String.trim()
  end

  defp render_resources(external_docs, source_context) do
    resources =
      [normalize_external_docs(external_docs), source_context_resource(source_context)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if resources == [] do
      nil
    else
      items =
        Enum.map_join(resources, "\n", fn resource ->
          label = resource.description || "Documentation"
          "  * [#{label}](#{resource.url})"
        end)

      """
      ## Resources

      #{items}
      """
      |> String.trim()
    end
  end

  defp render_code_samples([]), do: nil

  defp render_code_samples(code_samples) do
    blocks =
      Enum.map_join(code_samples, "\n\n", fn code_sample ->
        language = code_sample.language || "text"
        heading = present(code_sample.label)

        [heading, "```#{language}", code_sample.source || "", "```"]
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n")
      end)

    """
    ## Code Samples

    #{blocks}
    """
    |> String.trim()
  end

  defp render_source_context(nil), do: nil

  defp render_source_context(source_context) do
    source_context = normalize_source_context(source_context)

    lines =
      [
        "## Source Context",
        "",
        present(source_context.title),
        present(source_context.summary),
        present(source_context.description)
      ]
      |> Enum.reject(&blank?/1)

    if lines == [] do
      nil
    else
      Enum.join(lines, "\n")
    end
  end

  defp render_schema_fields([]), do: nil

  defp render_schema_fields(fields) do
    items =
      Enum.map_join(fields, "\n", fn field ->
        description =
          field.description ||
            if(field.required, do: "required", else: "optional")

        "  * `#{field.name}`: #{description}"
      end)

    """
    ## Fields

    #{items}
    """
    |> String.trim()
  end

  defp operation_summary(operation, source_context) do
    Map.get(operation, :summary) ||
      source_context_summary(source_context) ||
      "#{operation_method(operation)} `#{operation_path(operation)}`"
  end

  defp resolve_source_context(operation, opts) do
    Keyword.get_lazy(opts, :source_context, fn ->
      opts
      |> Keyword.get(:source_contexts, %{})
      |> source_context_for_operation(operation)
    end)
  end

  defp source_context_for_operation(source_contexts, operation) when is_map(source_contexts) do
    Map.get(source_contexts, {operation_method(operation), operation_path(operation)})
  end

  defp source_context_for_operation(_source_contexts, _operation), do: nil

  defp operation_method(operation) do
    Map.get(operation, :method, Map.get(operation, :request_method))
  end

  defp operation_path(operation) do
    Map.get(operation, :path, Map.get(operation, :request_path))
  end

  defp operation_response_docs(operation) do
    Map.get(operation, :response_docs, [])
  end

  defp normalize_params(params) do
    Enum.map(params, fn param ->
      %{
        name: Map.get(param, :name),
        description: Map.get(param, :description),
        required: Map.get(param, :required, false),
        deprecated: Map.get(param, :deprecated, false),
        example: normalize_value(Map.get(param, :example)),
        examples: normalize_value(Map.get(param, :examples)),
        location: Map.get(param, :location),
        style: Map.get(param, :style),
        explode: Map.get(param, :explode, false),
        value_type: Map.get(param, :value_type),
        extensions: normalize_map(Map.get(param, :extensions, %{}))
      }
    end)
  end

  defp normalize_request_body(request_body) when request_body in [nil, []], do: nil

  defp normalize_request_body(request_body) when is_list(request_body) do
    %{
      description: nil,
      required: request_body != [],
      content_types:
        request_body
        |> Enum.map(fn
          {content_type, _type} -> content_type
          other -> inspect(other)
        end)
        |> Enum.uniq()
    }
  end

  defp normalize_request_body(request_body) do
    %{
      description: Map.get(request_body, :description),
      required: Map.get(request_body, :required, false),
      content_types: Map.get(request_body, :content_types, [])
    }
  end

  defp normalize_responses(response_docs) do
    Enum.map(response_docs, fn response ->
      %{
        status: Map.get(response, :status),
        description: Map.get(response, :description),
        content_types: Map.get(response, :content_types, [])
      }
    end)
  end

  defp source_context_summary(nil), do: nil

  defp source_context_summary(%SourceContext{summary: summary, title: title}),
    do: summary || title

  defp source_context_summary(source_context),
    do: Map.get(source_context, :summary) || Map.get(source_context, :title)

  defp source_context_code_samples(nil), do: []
  defp source_context_code_samples(%SourceContext{code_samples: code_samples}), do: code_samples

  defp source_context_code_samples(source_context) do
    source_context
    |> Map.get(:code_samples, Map.get(source_context, "code_samples", []))
    |> normalize_code_samples()
  end

  defp source_context_resource(nil), do: nil

  defp source_context_resource(source_context) do
    source_context = normalize_source_context(source_context)

    if blank?(source_context.url) do
      nil
    else
      %{
        description: source_context.title || source_context.summary || "Source Context",
        url: source_context.url
      }
    end
  end

  defp normalize_source_context(nil), do: nil
  defp normalize_source_context(%SourceContext{} = source_context), do: source_context

  defp normalize_source_context(source_context) when is_map(source_context) do
    %{
      title: Map.get(source_context, :title) || Map.get(source_context, "title"),
      summary: Map.get(source_context, :summary) || Map.get(source_context, "summary"),
      description:
        Map.get(source_context, :description) || Map.get(source_context, "description"),
      url:
        Map.get(source_context, :url) || Map.get(source_context, "url") ||
          Map.get(source_context, :source_url) || Map.get(source_context, "source_url")
    }
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

  defp normalize_code_samples(code_samples) when is_list(code_samples) do
    Enum.map(code_samples, fn
      %_{} = code_sample ->
        code_sample

      code_sample when is_map(code_sample) ->
        %{
          language:
            Map.get(code_sample, :language) || Map.get(code_sample, "language") ||
              Map.get(code_sample, :lang) || Map.get(code_sample, "lang"),
          label: Map.get(code_sample, :label) || Map.get(code_sample, "label"),
          source:
            Map.get(code_sample, :source) || Map.get(code_sample, "source") ||
              Map.get(code_sample, :content) || Map.get(code_sample, "content")
        }

      code_sample ->
        %{language: nil, label: nil, source: inspect(code_sample)}
    end)
  end

  defp normalize_code_samples(_code_samples), do: []

  defp schema_title(schema) do
    cond do
      present(Map.get(schema, :title)) ->
        Map.get(schema, :title)

      is_atom(Map.get(schema, :module_name)) and Map.get(schema, :type_name) in [nil, :t] ->
        inspect(Map.get(schema, :module_name))

      is_atom(Map.get(schema, :module_name)) and is_atom(Map.get(schema, :type_name)) ->
        "#{inspect(Map.get(schema, :module_name))}.#{Map.get(schema, :type_name)}"

      is_atom(Map.get(schema, :type_name)) ->
        Atom.to_string(Map.get(schema, :type_name))

      true ->
        ""
    end
  end

  defp render_status(:default), do: "default"
  defp render_status(status), do: to_string(status)

  defp render_security_requirement(requirement) when is_map(requirement) do
    requirement
    |> Enum.map(fn {scheme, scopes} ->
      if scopes in [nil, []] do
        "`#{scheme}`"
      else
        "`#{scheme}` (#{Enum.join(scopes, ", ")})"
      end
    end)
    |> Enum.join(" or ")
  end

  defp render_security_requirement(requirement), do: inspect(requirement)

  defp normalize_map(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_map(other), do: normalize_value(other)

  defp normalize_value(%_{} = struct), do: struct |> Map.from_struct() |> normalize_map()
  defp normalize_value(map) when is_map(map), do: normalize_map(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp plural(list, singular) do
    if length(list) == 1, do: singular, else: singular <> "s"
  end

  defp finalize_doc(doc) do
    if String.contains?(doc, "\n"), do: doc <> "\n", else: doc
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp blank?(value), do: value in [nil, ""]
end
