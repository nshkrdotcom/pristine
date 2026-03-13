if Code.ensure_loaded?(OpenAPI.Renderer) do
  defmodule Pristine.OpenAPI.Renderer do
    @moduledoc """
    Renderer overrides for Pristine-targeted generated operation surfaces.

    The default upstream renderer stays in place for modules, schemas, docs, and
    file layout. This module only overrides the operation shape so generated code
    can accept a single params map and emit Pristine request partitions.
    """

    use OpenAPI.Renderer

    alias OpenAPI.Processor.Operation
    alias OpenAPI.Processor.Operation.Param
    alias OpenAPI.Processor.Schema, as: ProcessedSchema
    alias OpenAPI.Renderer.File
    alias OpenAPI.Renderer.Operation, as: OperationRenderer
    alias OpenAPI.Renderer.Schema, as: SchemaRenderer
    alias OpenAPI.Renderer.State
    alias OpenAPI.Renderer.Util
    alias Pristine.OpenAPI.DocComposer
    alias Pristine.OpenAPI.Runtime, as: OpenAPIRuntime
    alias Pristine.OpenAPI.SchemaMaterialization

    @multipart_content_type "multipart/form-data"
    @nested_module_alias_rewrites [
      {[:Pristine, :OAuth2], [:OAuth2], quote(do: alias(Pristine.OAuth2, as: OAuth2))},
      {[:Pristine, :OpenAPI, :Runtime], [:OpenAPIRuntime],
       quote(do: alias(Pristine.OpenAPI.Runtime, as: OpenAPIRuntime))}
    ]
    @nested_module_alias_source_rewrites [
      {"Pristine.OAuth2", "OAuth2", "alias Pristine.OAuth2, as: OAuth2"},
      {"Pristine.OpenAPI.Runtime", "OpenAPIRuntime",
       "alias Pristine.OpenAPI.Runtime, as: OpenAPIRuntime"}
    ]

    @impl OpenAPI.Renderer
    def render(state, file) do
      OpenAPI.Renderer.render(state, file)
    end

    @impl OpenAPI.Renderer
    def format(state, file) do
      state
      |> OpenAPI.Renderer.format(file)
      |> rewrite_nested_module_aliases_in_source()
    end

    @impl OpenAPI.Renderer
    def render_moduledoc(state, file) do
      moduledoc = DocComposer.module_doc(file, source_contexts: source_contexts(state))
      quote do: @moduledoc(unquote(moduledoc))
    end

    @impl OpenAPI.Renderer
    def render_operations(_state, %File{operations: []}), do: []

    def render_operations(state, file) do
      OpenAPI.Renderer.render_operations(state, file)
    end

    @impl OpenAPI.Renderer
    def render_operation_doc(state, operation) do
      docstring = DocComposer.operation_doc(operation, source_contexts: source_contexts(state))
      quote do: @doc(unquote(docstring))
    end

    @impl OpenAPI.Renderer
    def render_operation_spec(state, operation) do
      %Operation{function_name: name, responses: responses} = operation

      params = quote(do: params :: map())
      opts = quote(do: opts :: keyword())
      return_type = render_return_type(state, responses)

      case config(state)[:types][:specs] do
        false ->
          []

        :callback ->
          quote do
            @callback unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
          end

        :callback_comprehensive ->
          [
            quote do
              @callback unquote(name)(unquote(params)) :: unquote(return_type)
            end,
            quote do
              @callback unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
            end
          ]

        :spec_comprehensive ->
          [
            quote do
              @spec unquote(name)(unquote(params)) :: unquote(return_type)
            end,
            quote do
              @spec unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
            end
          ]

        _default ->
          quote do
            @spec unquote(name)(unquote(params), unquote(opts)) :: unquote(return_type)
          end
      end
    end

    @impl OpenAPI.Renderer
    def render_operation_function(state, operation) do
      %Operation{
        function_name: function_name,
        module_name: module_name,
        request_body: request_body,
        request_method: request_method,
        request_path: request_path,
        responses: responses
      } = operation

      partition_spec = request_partition_spec(state, operation)

      module_name =
        Module.concat([
          config(state)[:base_module],
          module_name
        ])

      request =
        [
          quote(do: {:args, params}),
          quote(do: {:call, {unquote(module_name), unquote(function_name)}}),
          quote(do: {:url, render_path(unquote(request_path), partition.path_params)}),
          quote(do: {:method, unquote(request_method)}),
          quote(do: {:path_params, partition.path_params}),
          quote(do: {:query, partition.query}),
          quote(do: {:body, partition.body}),
          quote(do: {:form_data, partition.form_data}),
          quote(do: {:auth, partition.auth}),
          render_security_info(state, operation),
          OperationRenderer.render_call_request_info(
            state,
            request_body,
            config(state)[:operation_call][:request]
          ),
          render_response_info(state, responses),
          quote(do: {:opts, opts})
        ]
        |> Enum.reject(&is_nil/1)

      quote do
        def unquote(function_name)(params \\ %{}, opts \\ [])
            when is_map(params) and is_list(opts) do
          client = opts[:client] || @default_client
          partition = partition(params, unquote(Macro.escape(partition_spec)))

          client.request(%{
            unquote_splicing(request)
          })
        end
      end
    end

    @impl OpenAPI.Renderer
    def render_schema(state, %File{module: module, operations: operations, schemas: schemas}) do
      %State{implementation: implementation} = state

      structured_schemas =
        schemas
        |> Enum.filter(&(&1.output_format == :struct))
        |> merge_schema_groups(state)

      runtime_schemas =
        schemas
        |> Enum.filter(fn
          %ProcessedSchema{output_format: :struct} ->
            true

          %ProcessedSchema{output_format: :typed_map} = schema ->
            SchemaMaterialization.materialized_typed_map?(schema, module, state.schemas)

          _other ->
            false
        end)
        |> merge_schema_groups(state)

      types =
        cond do
          runtime_schemas == [] ->
            []

          operations == [] ->
            implementation.render_schema_types(state, runtime_schemas)

          true ->
            implementation.render_schema_types(state, structured_schemas)
        end

      struct =
        if structured_schemas == [] do
          []
        else
          implementation.render_schema_struct(state, structured_schemas)
        end

      runtime_helpers =
        if runtime_schemas == [] do
          []
        else
          implementation.render_schema_field_function(state, runtime_schemas)
        end

      Util.clean_list([types, struct, runtime_helpers])
    end

    @impl OpenAPI.Renderer
    def render_schema_field_function(state, schemas) do
      default = SchemaRenderer.render_field_function(state, schemas)

      runtime_helpers =
        if schemas == [] do
          []
        else
          default_type =
            schemas
            |> Enum.map(& &1.type_name)
            |> Enum.sort()
            |> then(fn [first | _] = types -> Enum.find(types, first, &(&1 == :t)) end)

          [
            render_openapi_field_function(state, schemas, default_type),
            render_schema_function(schemas, default_type),
            render_decode_function(default_type)
          ]
        end

      Util.clean_list([default, runtime_helpers])
    end

    defp request_partition_spec(state, operation) do
      %Operation{
        request_body: request_body,
        request_path_parameters: path_params,
        request_query_parameters: query_params
      } = operation

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

    defp payload_spec(_state, [], _fallback_key), do: %{mode: :none}

    defp payload_spec(state, request_body, fallback_key) do
      keys =
        request_body
        |> Enum.reduce(MapSet.new(), fn {_content_type, type}, keys ->
          MapSet.union(keys, request_field_names(state, type))
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
      Enum.map(params, fn %Param{name: name} -> {name, String.to_atom(name)} end)
    end

    defp request_field_names(state, {:union, types}) do
      Enum.reduce(types, MapSet.new(), fn type, names ->
        MapSet.union(names, request_field_names(state, type))
      end)
    end

    defp request_field_names(state, ref) when is_reference(ref) do
      case Map.get(state.schemas, ref) do
        %{fields: fields} ->
          Enum.reduce(fields, MapSet.new(), fn field, names -> MapSet.put(names, field.name) end)

        nil ->
          MapSet.new()
      end
    end

    defp request_field_names(_state, _type), do: MapSet.new()

    defp render_security_info(
           state,
           %Operation{request_method: method, request_path: path} = operation
         ) do
      security =
        if is_nil(Map.get(operation, :security)) do
          fallback_security_for_operation(state, method, path)
        else
          Map.get(operation, :security)
        end
        |> normalize_security_requirements()

      case security do
        nil -> nil
        security -> quote(do: {:security, unquote(Macro.escape(security))})
      end
    end

    defp fallback_security_for_operation(state, method, path) do
      state
      |> config()
      |> security_metadata()
      |> Map.get(:operations, %{})
      |> Map.get({method, path})
    end

    defp normalize_security_requirements(nil), do: nil
    defp normalize_security_requirements(security) when is_list(security), do: Enum.uniq(security)
    defp normalize_security_requirements(security), do: security

    defp render_response_info(_state, []), do: nil

    defp render_response_info(state, responses) do
      items =
        responses
        |> Enum.sort_by(fn {status_or_default, _schemas} -> status_or_default end)
        |> Enum.map(fn {status_or_default, schemas} ->
          type = Util.to_readable_type(state, {:union, Map.values(schemas)})

          quote do
            {unquote(status_or_default), unquote(type)}
          end
        end)

      quote do
        {:response, unquote(items)}
      end
    end

    defp render_return_type(_state, []), do: quote(do: :ok)

    defp render_return_type(state, responses) do
      %State{implementation: implementation} = state

      {success, error} =
        responses
        |> Enum.reject(fn {status, schemas} ->
          map_size(schemas) == 0 or (status >= 300 and status < 400)
        end)
        |> Enum.split_with(fn {status, _schemas} -> status < 300 end)

      ok =
        if success == [] do
          quote(do: :ok)
        else
          type =
            success
            |> Enum.flat_map(fn {_status, schemas} -> Map.values(schemas) end)
            |> then(&implementation.render_type(state, {:union, &1}))

          quote(do: {:ok, unquote(type)})
        end

      error =
        case config(state)[:types][:error] do
          nil ->
            render_error_union(state, error)

          error_type ->
            quote(do: {:error, unquote(render_configured_type(state, error_type))})
        end

      {:|, [], [ok, error]}
    end

    defp render_error_union(_state, []), do: quote(do: :error)

    defp render_error_union(state, error) do
      %State{implementation: implementation} = state

      type =
        error
        |> Enum.flat_map(fn {_status, schemas} -> Map.values(schemas) end)
        |> then(&implementation.render_type(state, {:union, &1}))

      quote(do: {:error, unquote(type)})
    end

    defp render_configured_type(state, {module, type}) when is_atom(module) and is_atom(type) do
      %State{implementation: implementation} = state
      implementation.render_type(state, {module, type})
    end

    defp render_configured_type(_state, module) when is_atom(module) do
      quote(do: unquote(module).t())
    end

    defp render_openapi_field_function(state, schemas, default_type) do
      typespec =
        quote do
          @doc false
          @spec __openapi_fields__(atom) :: [map()]
        end

      header =
        quote do
          def __openapi_fields__(type \\ unquote(default_type))
        end

      clauses =
        Enum.map(schemas, fn %ProcessedSchema{fields: fields, type_name: type_name} = schema ->
          openapi_fields =
            fields
            |> Enum.reject(& &1.private)
            |> Enum.sort_by(& &1.name)
            |> Enum.map(&render_openapi_field(state, schema, &1))

          quote do
            def __openapi_fields__(unquote(type_name)) do
              unquote(Macro.escape(openapi_fields))
            end
          end
        end)

      Util.clean_list([typespec, header, clauses])
    end

    defp render_openapi_field(state, schema, field) do
      metadata =
        case resolve_raw_field_spec(state, schema, field.name) do
          nil -> %{}
          raw_field -> raw_field_metadata(raw_field)
        end

      rendered_type = Util.to_readable_type(state, field.type)

      field =
        %{
          default: first_non_nil(Map.get(field, :default), Map.get(metadata, :default)),
          description:
            first_non_nil(Map.get(field, :description), Map.get(metadata, :description)),
          deprecated: Map.get(field, :deprecated, false) or Map.get(metadata, :deprecated, false),
          example: first_non_nil(Map.get(field, :example), Map.get(metadata, :example)),
          examples: first_non_nil(Map.get(field, :examples), Map.get(metadata, :examples)),
          external_docs:
            first_non_nil(Map.get(field, :external_docs), Map.get(metadata, :external_docs)),
          extensions:
            Map.merge(Map.get(metadata, :extensions, %{}), Map.get(field, :extensions, %{})),
          name: field.name,
          nullable: Map.get(field, :nullable, false),
          read_only: Map.get(field, :read_only, false) or Map.get(metadata, :read_only, false),
          required: Map.get(field, :required, false),
          write_only: Map.get(field, :write_only, false) or Map.get(metadata, :write_only, false)
        }

      DocComposer.field(field, rendered_type)
    end

    defp resolve_raw_field_spec(state, schema, field_name) do
      with raw_schema when not is_nil(raw_schema) <- resolve_raw_schema_spec(state, schema),
           properties when is_map(properties) <- Map.get(raw_schema, :properties) do
        properties
        |> Map.get(field_name)
        |> resolve_schema_spec(state)
      end
    end

    defp resolve_raw_schema_spec(state, %ProcessedSchema{context: contexts}) do
      Enum.find_value(contexts, &resolve_raw_schema_context(state, &1))
    end

    defp resolve_raw_schema_context(
           state,
           {:response, module_name, function_name, status, content_type}
         ) do
      with operation when not is_nil(operation) <-
             resolve_processed_operation(state, module_name, function_name),
           raw_operation when not is_nil(raw_operation) <-
             resolve_raw_operation_spec(state, operation),
           response when not is_nil(response) <-
             Map.get(Map.get(raw_operation, :responses, %{}), status),
           media when not is_nil(media) <- Map.get(Map.get(response, :content, %{}), content_type) do
        resolve_schema_spec(Map.get(media, :schema), state)
      end
    end

    defp resolve_raw_schema_context(state, {:request, module_name, function_name, content_type}) do
      with operation when not is_nil(operation) <-
             resolve_processed_operation(state, module_name, function_name),
           raw_operation when not is_nil(raw_operation) <-
             resolve_raw_operation_spec(state, operation),
           request_body when not is_nil(request_body) <- Map.get(raw_operation, :request_body),
           media when not is_nil(media) <-
             Map.get(Map.get(request_body, :content, %{}), content_type) do
        resolve_schema_spec(Map.get(media, :schema), state)
      end
    end

    defp resolve_raw_schema_context(state, {:field, parent_ref, field_name}) do
      with parent when not is_nil(parent) <- Map.get(state.schemas, parent_ref),
           raw_parent when not is_nil(raw_parent) <- resolve_raw_schema_spec(state, parent),
           properties when is_map(properties) <- Map.get(raw_parent, :properties) do
        properties
        |> Map.get(field_name)
        |> resolve_schema_spec(state)
      end
    end

    defp resolve_raw_schema_context(_state, _context), do: nil

    defp resolve_processed_operation(state, module_name, function_name) do
      Enum.find(state.operations, fn operation ->
        operation.module_name == module_name and operation.function_name == function_name
      end)
    end

    defp resolve_raw_operation_spec(state, operation) do
      with spec when not is_nil(spec) <- config(state)[:spec_metadata_source],
           path_item when not is_nil(path_item) <-
             Map.get(Map.get(spec, :paths, %{}), operation.request_path) do
        Map.get(path_item, operation.request_method)
      end
    end

    defp resolve_schema_spec(nil, _state), do: nil

    defp resolve_schema_spec({:ref, full_path}, state) do
      state
      |> config()
      |> Keyword.get(:schema_specs_by_path, %{})
      |> Map.get(full_path)
      |> resolve_schema_spec(state)
    end

    defp resolve_schema_spec(schema, _state), do: schema

    defp raw_field_metadata(raw_field) do
      %{
        default: Map.get(raw_field, :default),
        description: Map.get(raw_field, :description),
        deprecated: Map.get(raw_field, :deprecated, false),
        example: Map.get(raw_field, :example),
        examples: Map.get(raw_field, :examples),
        external_docs: Map.get(raw_field, :external_docs),
        extensions: raw_schema_extensions(raw_field),
        read_only: Map.get(raw_field, :read_only, false),
        write_only: Map.get(raw_field, :write_only, false)
      }
    end

    defp raw_schema_extensions(raw_field) do
      with file when is_binary(file) <- Map.get(raw_field, :"$oag_last_ref_file"),
           path when is_list(path) <- Map.get(raw_field, :"$oag_last_ref_path"),
           source when is_map(source) <- read_openapi_source(file),
           raw_value when is_map(raw_value) <- get_in(source, path) do
        raw_value
        |> Enum.filter(fn {key, _value} -> String.starts_with?(to_string(key), "x-") end)
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
      else
        _other -> %{}
      end
    end

    defp read_openapi_source(path) do
      case Path.extname(path) do
        ext when ext in [".yaml", ".yml"] ->
          YamlElixir.read_from_file!(path)

        ".json" ->
          path |> Elixir.File.read!() |> Jason.decode!()

        _other ->
          contents = Elixir.File.read!(path)

          case Jason.decode(contents) do
            {:ok, decoded} -> decoded
            {:error, _reason} -> YamlElixir.read_from_file!(path)
          end
      end
    end

    defp render_schema_function(schemas, default_type) do
      typespec =
        quote do
          @doc false
          @spec __schema__(atom) :: Sinter.Schema.t()
        end

      header =
        quote do
          def __schema__(type \\ unquote(default_type))
        end

      clauses =
        Enum.map(schemas, fn %ProcessedSchema{type_name: type_name} ->
          quote do
            def __schema__(unquote(type_name)) do
              OpenAPIRuntime.build_schema(__openapi_fields__(unquote(type_name)))
            end
          end
        end)

      Util.clean_list([typespec, header, clauses])
    end

    defp render_decode_function(default_type) do
      quote do
        @doc false
        @spec decode(term(), atom) :: {:ok, term()} | {:error, term()}
        def decode(data, type \\ unquote(default_type))

        def decode(data, type) do
          OpenAPIRuntime.decode_module_type(__MODULE__, type, data)
        end
      end
    end

    defp merge_schema_groups(schemas, state) do
      schemas
      |> Enum.group_by(&{&1.module_name, &1.type_name})
      |> Enum.map(fn {_module_and_type, grouped} ->
        grouped
        |> Enum.sort_by(&schema_group_sort_key(&1, state.schemas))
        |> Enum.reduce(&ProcessedSchema.merge/2)
      end)
      |> List.flatten()
      |> Enum.sort_by(& &1.type_name)
    end

    defp schema_group_sort_key(%ProcessedSchema{} = schema, schemas_by_ref) do
      [
        module_name: module_name_string(schema.module_name),
        type_name: atom_to_string(schema.type_name),
        output_format: atom_to_string(schema.output_format),
        context:
          schema.context
          |> Enum.map(&normalize_schema_term(&1, schemas_by_ref))
          |> Enum.sort(),
        fields:
          schema.fields
          |> Enum.map(&normalize_schema_field(&1, schemas_by_ref))
          |> Enum.sort()
      ]
    end

    defp normalize_schema_field(field, schemas_by_ref) do
      [
        name: field.name,
        default: normalize_schema_term(field.default, schemas_by_ref),
        type: normalize_schema_term(field.type, schemas_by_ref),
        required: field.required,
        nullable: field.nullable,
        private: field.private
      ]
    end

    defp normalize_schema_term(reference, schemas_by_ref) when is_reference(reference) do
      case Map.get(schemas_by_ref, reference) do
        %ProcessedSchema{} = schema ->
          {:schema_ref, shallow_schema_identity(schema)}

        nil ->
          {:schema_ref, "missing"}
      end
    end

    defp normalize_schema_term(%_{} = struct, schemas_by_ref) do
      struct
      |> Map.from_struct()
      |> normalize_schema_term(schemas_by_ref)
    end

    defp normalize_schema_term(map, schemas_by_ref) when is_map(map) do
      map
      |> Enum.map(fn {key, value} ->
        {normalize_schema_term(key, schemas_by_ref), normalize_schema_term(value, schemas_by_ref)}
      end)
      |> Enum.sort()
    end

    defp normalize_schema_term(tuple, schemas_by_ref) when is_tuple(tuple) do
      tuple
      |> Tuple.to_list()
      |> Enum.map(&normalize_schema_term(&1, schemas_by_ref))
      |> List.to_tuple()
    end

    defp normalize_schema_term(list, schemas_by_ref) when is_list(list) do
      Enum.map(list, &normalize_schema_term(&1, schemas_by_ref))
    end

    defp normalize_schema_term(atom, _schemas_by_ref) when is_atom(atom), do: Atom.to_string(atom)
    defp normalize_schema_term(value, _schemas_by_ref), do: value

    defp shallow_schema_identity(%ProcessedSchema{} = schema) do
      [
        module_name: module_name_string(schema.module_name),
        type_name: atom_to_string(schema.type_name),
        output_format: atom_to_string(schema.output_format),
        field_names: schema.fields |> Enum.map(& &1.name) |> Enum.sort()
      ]
    end

    defp module_name_string(nil), do: nil
    defp module_name_string(module_name) when is_atom(module_name), do: inspect(module_name)

    defp atom_to_string(nil), do: nil
    defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

    @doc false
    def rewrite_nested_module_aliases(nil), do: nil

    def rewrite_nested_module_aliases({:defmodule, meta, [module_name, [do: body]]}) do
      {rewritten_body, used_prefixes} =
        Macro.prewalk(body, MapSet.new(), fn
          {:__aliases__, alias_meta, segments} = node, used_prefixes ->
            case rewrite_alias_segments(segments) do
              {:rewrite, full_prefix, rewritten_segments} ->
                {{:__aliases__, alias_meta, rewritten_segments},
                 MapSet.put(used_prefixes, full_prefix)}

              :no_rewrite ->
                {node, used_prefixes}
            end

          node, used_prefixes ->
            {node, used_prefixes}
        end)

      rewrites =
        Enum.filter(@nested_module_alias_rewrites, fn {full_prefix, _short_prefix, _declaration} ->
          MapSet.member?(used_prefixes, full_prefix)
        end)

      body_expressions = body_to_expressions(rewritten_body)
      insertion_index = body_expressions |> Enum.take_while(&header_expression?/1) |> length()
      alias_declarations = Enum.map(rewrites, &elem(&1, 2))
      {prefix, suffix} = Enum.split(body_expressions, insertion_index)

      {:defmodule, meta,
       [module_name, [do: expressions_to_body(prefix ++ alias_declarations ++ suffix)]]}
    end

    def rewrite_nested_module_aliases(ast), do: ast

    defp body_to_expressions({:__block__, _meta, expressions}), do: expressions
    defp body_to_expressions(nil), do: []
    defp body_to_expressions(expression), do: [expression]

    defp expressions_to_body([]), do: nil
    defp expressions_to_body([expression]), do: expression
    defp expressions_to_body(expressions), do: {:__block__, [], expressions}

    defp header_expression?({:@, _meta, [{:moduledoc, _, _}]}), do: true
    defp header_expression?({:use, _meta, _args}), do: true
    defp header_expression?({:import, _meta, _args}), do: true
    defp header_expression?({:require, _meta, _args}), do: true
    defp header_expression?({:alias, _meta, _args}), do: true
    defp header_expression?(_expression), do: false

    defp rewrite_alias_segments(segments) do
      Enum.find_value(@nested_module_alias_rewrites, :no_rewrite, fn
        {full_prefix, short_prefix, _declaration} ->
          if alias_prefix?(segments, full_prefix) do
            {:rewrite, full_prefix, short_prefix ++ Enum.drop(segments, length(full_prefix))}
          end
      end)
    end

    defp alias_prefix?(segments, full_prefix) do
      Enum.take(segments, length(full_prefix)) == full_prefix
    end

    @doc false
    def rewrite_nested_module_aliases_in_source(contents) do
      source = IO.iodata_to_binary(contents)

      rewrites =
        Enum.filter(@nested_module_alias_source_rewrites, fn {full, short, _declaration} ->
          String.contains?(source, full <> ".") or String.contains?(source, short <> ".")
        end)

      source =
        Enum.reduce(rewrites, source, fn {full, short, _declaration}, acc ->
          String.replace(acc, full <> ".", short <> ".")
        end)

      insert_nested_module_alias_lines(source, rewrites)
    end

    defp insert_nested_module_alias_lines(source, []), do: source

    defp insert_nested_module_alias_lines(source, rewrites) do
      lines = String.split(source, "\n", trim: false)

      alias_lines =
        rewrites
        |> Enum.map(&elem(&1, 2))
        |> Enum.reject(&String.contains?(source, &1))
        |> Enum.map(&("  " <> &1))

      if alias_lines == [] do
        source
      else
        insertion_index = nested_module_alias_source_insertion_index(lines)
        {prefix, suffix} = Enum.split(lines, insertion_index)

        separator =
          case suffix do
            ["" | _rest] -> []
            [] -> []
            _other -> [""]
          end

        Enum.join(prefix ++ alias_lines ++ separator ++ suffix, "\n")
      end
    end

    defp nested_module_alias_source_insertion_index(lines) do
      lines
      |> skip_module_declaration(0)
      |> skip_moduledoc_block(lines)
      |> skip_top_level_directives(lines)
    end

    defp skip_module_declaration(lines, index) do
      case Enum.at(lines, index) do
        line when is_binary(line) ->
          if String.starts_with?(line, "defmodule "), do: index + 1, else: index

        _ ->
          index
      end
    end

    defp skip_moduledoc_block(index, lines) do
      case Enum.at(lines, index) do
        line when is_binary(line) ->
          if Regex.match?(~r/^\s*@moduledoc\b/, line) do
            moduledoc_block_end_index(index, line, lines)
          else
            index
          end

        _ ->
          index
      end
    end

    defp moduledoc_block_end_index(index, line, lines) do
      cond do
        not String.contains?(line, "\"\"\"") ->
          index + 1

        triple_quote_count(line) >= 2 ->
          index + 1

        true ->
          case Enum.find_index(Enum.drop(lines, index + 1), &String.contains?(&1, "\"\"\"")) do
            nil -> index + 1
            closing_offset -> index + closing_offset + 2
          end
      end
    end

    defp skip_top_level_directives(index, lines) do
      case Enum.at(lines, index) do
        line when is_binary(line) ->
          if Regex.match?(~r/^\s*(use|alias|require|import)\b/, line) do
            skip_top_level_directives(index + 1, lines)
          else
            index
          end

        _ ->
          index
      end
    end

    defp triple_quote_count(line) do
      line
      |> String.split("\"\"\"")
      |> length()
      |> Kernel.-(1)
    end

    defp config(%State{profile: profile}) do
      Application.get_env(:oapi_generator, profile, [])
      |> Keyword.get(:output, [])
    end

    defp security_metadata(output_config) do
      Keyword.get(output_config, :security_metadata) ||
        Keyword.get(output_config, :security_fallback_metadata) ||
        %{}
    end

    defp first_non_nil(nil, fallback), do: fallback
    defp first_non_nil(value, _fallback), do: value

    defp source_contexts(state) do
      config(state)[:source_contexts] || %{}
    end
  end
else
  defmodule Pristine.OpenAPI.Renderer do
    @moduledoc false

    def unavailable! do
      raise """
      oapi_generator is required to use Pristine.OpenAPI.Renderer.

      Add it as a build-time dependency, for example:

          {:oapi_generator, "~> 0.4", only: [:dev, :test], runtime: false}
      """
    end

    def rewrite_nested_module_aliases(ast), do: ast
    def rewrite_nested_module_aliases_in_source(contents), do: IO.iodata_to_binary(contents)
  end
end
