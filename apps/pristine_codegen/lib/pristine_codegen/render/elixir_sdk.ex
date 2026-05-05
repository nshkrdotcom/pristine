defmodule PristineCodegen.Render.ElixirSDK do
  @moduledoc """
  Shared Elixir SDK renderer that projects `PristineCodegen.ProviderIR` into
  generated provider client, operation, pagination, and type modules.
  """

  alias PristineCodegen.Identifier
  alias PristineCodegen.ProviderIR
  alias PristineCodegen.RenderedFile

  @spec render(ProviderIR.t()) :: [RenderedFile.t()]
  def render(%ProviderIR{} = provider_ir) do
    operation_modules =
      provider_ir.operations
      |> Enum.group_by(& &1.module)
      |> Enum.map(fn {module_name, operations} ->
        {module_name, Enum.sort_by(operations, & &1.id)}
      end)
      |> Enum.sort_by(fn {module_name, _operations} -> Module.split(module_name) end)

    schemas_by_module =
      provider_ir.schemas
      |> Enum.group_by(& &1.module)
      |> Map.new(fn {module_name, schemas} ->
        {module_name, Enum.sort_by(schemas, &{&1.type_name, &1.id})}
      end)

    runtime_schema_file = render_runtime_schema_file(provider_ir)
    client_file = render_client_file(provider_ir)

    operation_files =
      Enum.map(operation_modules, fn {module_name, operations} ->
        render_operation_file(
          provider_ir,
          module_name,
          operations,
          Map.get(schemas_by_module, module_name, [])
        )
      end)

    schema_files =
      provider_ir.schemas
      |> Enum.group_by(& &1.module)
      |> Enum.reject(fn {module_name, _schemas} ->
        Enum.any?(operation_modules, fn {operation_module, _operations} ->
          operation_module == module_name
        end)
      end)
      |> Enum.map(fn {module_name, schemas} ->
        render_schema_file(
          provider_ir,
          module_name,
          Enum.sort_by(schemas, &{&1.type_name, &1.id})
        )
      end)

    [runtime_schema_file, client_file | operation_files ++ schema_files]
  end

  defp render_runtime_schema_file(provider_ir) do
    module_source = provider_runtime_schema_module_source(provider_ir.provider.base_module)

    source = """
    defmodule #{module_source} do
      @moduledoc false

      alias Sinter.Schema

      @non_module_ref_heads [
        nil,
        true,
        false,
        :array,
        :boolean,
        :const,
        :enum,
        :integer,
        :literal,
        :map,
        :nullable,
        :number,
        :object,
        :string,
        :tuple,
        :union
      ]

      @spec build_schema([map()]) :: Schema.t()
      def build_schema(fields) when is_list(fields) do
        field_specs =
          Enum.map(fields, fn field ->
            type =
              field.type
              |> to_runtime_type()
              |> maybe_nullable(Map.get(field, :nullable, false))

            {
              field.name,
              type,
              field_opts(field)
            }
          end)

        Schema.define(field_specs)
      end

      @spec decode_module_type(module(), atom(), term()) :: {:ok, term()} | {:error, term()}
      def decode_module_type(module, type, data) when is_atom(module) and is_atom(type) do
        with {:ok, validated} <- Sinter.Validator.validate(schema_for(module, type), data) do
          {:ok, materialize_module(module, type, validated)}
        end
      end

      defp schema_for(module, type) do
        key = {__MODULE__, :schema, module, type}

        case :persistent_term.get(key, :missing) do
          :missing ->
            schema = module.__schema__(type)
            :persistent_term.put(key, schema)
            schema

          schema ->
            schema
        end
      end

      defp field_opts(field) do
        []
        |> maybe_put_required(Map.get(field, :required, false))
        |> maybe_put_default(Map.get(field, :default))
      end

      defp maybe_put_required(opts, true), do: Keyword.put(opts, :required, true)
      defp maybe_put_required(opts, _required), do: Keyword.put(opts, :optional, true)

      defp maybe_put_default(opts, nil), do: opts
      defp maybe_put_default(opts, default), do: Keyword.put(opts, :default, default)

      defp maybe_nullable(type, true), do: {:union, [type, :null]}
      defp maybe_nullable(type, false), do: type

      defp materialize_module(module, type, validated) do
        fields =
          if function_exported?(module, :__openapi_fields__, 1) do
            module.__openapi_fields__(type)
          else
            []
          end

        field_keys = materialize_field_keys(module)

        values =
          Enum.reduce(fields, %{}, fn field, acc ->
            put_materialized_field(acc, field_keys, validated, field)
          end)

        if function_exported?(module, :__struct__, 0) do
          struct(module, values)
        else
          values
        end
      end

      defp put_materialized_field(acc, field_keys, validated, field) do
        with {:ok, value} <- Map.fetch(validated, field.name),
             {:ok, key} <- materialize_field_key(field_keys, field.name) do
          Map.put(acc, key, materialize_openapi_value(field.type, value))
        else
          _other -> acc
        end
      end

      defp materialize_field_keys(module) do
        if function_exported?(module, :__struct__, 0) do
          cached_struct_field_keys(module)
        else
          :string_keys
        end
      end

      defp cached_struct_field_keys(module) do
        key = {__MODULE__, :field_keys, module}

        case :persistent_term.get(key, :missing) do
          :missing ->
            keys =
              module
              |> struct_field_keys()
              |> Map.new(&{Atom.to_string(&1), &1})

            :persistent_term.put(key, keys)
            keys

          keys ->
            keys
        end
      end

      defp materialize_field_key(:string_keys, field_name), do: {:ok, field_name}
      defp materialize_field_key(field_keys, field_name), do: Map.fetch(field_keys, field_name)

      defp struct_field_keys(module) do
        module.__struct__()
        |> Map.keys()
        |> Enum.reject(&(&1 == :__struct__))
      end

      defp materialize_openapi_value(_type, nil), do: nil

      defp materialize_openapi_value({module, type}, value)
           when is_map(value) and is_atom(module) and is_atom(type) do
        case invoke_module_decode(module, type, value) do
          {:ok, materialized} -> materialized
          {:error, _reason} -> value
        end
      end

      defp materialize_openapi_value([inner], value) when is_list(value) do
        Enum.map(value, &materialize_openapi_value(inner, &1))
      end

      defp materialize_openapi_value({:array, inner}, value) when is_list(value) do
        Enum.map(value, &materialize_openapi_value(inner, &1))
      end

      defp materialize_openapi_value({:union, types}, value) do
        choose_union_candidate(types, value, &materialize_openapi_value(&1, value))
      end

      defp materialize_openapi_value({:string, "date"}, value) when is_binary(value) do
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          _ -> value
        end
      end

      defp materialize_openapi_value({:string, "date-time"}, value) when is_binary(value) do
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            datetime

          _ ->
            case NaiveDateTime.from_iso8601(value) do
              {:ok, datetime} -> datetime
              _ -> value
            end
        end
      end

      defp materialize_openapi_value({:string, "time"}, value) when is_binary(value) do
        case Time.from_iso8601(value) do
          {:ok, time} -> time
          _ -> value
        end
      end

      defp materialize_openapi_value(_type, value), do: value

      defp union_candidate_changed?({module, type}, value) when is_atom(module) and is_atom(type) do
        case invoke_module_decode(module, type, value) do
          {:ok, materialized} -> materialized != value
          {:error, _} -> false
        end
      end

      defp union_candidate_changed?({:string, format}, value)
           when format in ["date", "date-time", "time"] and is_binary(value) do
        materialize_openapi_value({:string, format}, value) != value
      end

      defp union_candidate_changed?([inner], value) when is_list(value) do
        Enum.any?(value, &(materialize_openapi_value(inner, &1) != &1))
      end

      defp union_candidate_changed?({:array, inner}, value) when is_list(value) do
        Enum.any?(value, &(materialize_openapi_value(inner, &1) != &1))
      end

      defp union_candidate_changed?(_type, _value), do: false

      defp choose_union_candidate(types, value, materialize_fun) do
        types
        |> Enum.reduce([], fn type, candidates ->
          case union_match_score(type, value) do
            nil ->
              candidates

            score ->
              [{score, materialize_fun.(type)} | candidates]
          end
        end)
        |> case do
          [] ->
            value

          candidates ->
            candidates
            |> Enum.max_by(fn {score, _candidate} -> score end)
            |> elem(1)
        end
      end

      defp union_match_score({module, type}, value)
           when is_map(value) and is_atom(module) and is_atom(type) do
        case invoke_module_decode(module, type, value) do
          {:ok, _materialized} -> schema_field_count(module, type)
          {:error, _reason} -> nil
        end
      end

      defp union_match_score({:union, types}, value) do
        types
        |> Enum.map(&union_match_score(&1, value))
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          scores -> Enum.max(scores)
        end
      end

      defp union_match_score([inner], value) when is_list(value) do
        1 + Enum.reduce(value, 0, fn item, total -> total + (union_match_score(inner, item) || 0) end)
      end

      defp union_match_score({:array, inner}, value) when is_list(value) do
        1 + Enum.reduce(value, 0, fn item, total -> total + (union_match_score(inner, item) || 0) end)
      end

      defp union_match_score({:string, format}, value)
           when format in ["date", "date-time", "time"] and is_binary(value) do
        if union_candidate_changed?({:string, format}, value), do: 1, else: nil
      end

      defp union_match_score(type, value) do
        if union_candidate_changed?(type, value), do: 1, else: nil
      end

      defp schema_field_count(module, type) do
        cond do
          function_exported?(module, :__openapi_fields__, 1) ->
            module.__openapi_fields__(type) |> length()

          function_exported?(module, :__fields__, 1) ->
            module.__fields__(type) |> length()

          true ->
            0
        end
      end

      defp specificity_score({:object, %Schema{fields: fields}}), do: map_size(fields)
      defp specificity_score(%Schema{fields: fields}), do: map_size(fields)
      defp specificity_score({:array, inner}), do: specificity_score(inner)
      defp specificity_score([inner]), do: specificity_score(inner)

      defp specificity_score({:union, types}) do
        Enum.max(Enum.map(types, &specificity_score/1), fn -> 0 end)
      end

      defp specificity_score(_type), do: 0

      defp resolve_type_spec({module, type}, _type_schemas, top_level?)
           when is_atom(module) and is_atom(type) and module not in @non_module_ref_heads do
        ensure_module_loaded!(module)

        resolved =
          cond do
            function_exported?(module, :__schema__, 1) ->
              module.__schema__(type)

            function_exported?(module, :schema, 0) and type == :t ->
              module.schema()

            true ->
              raise ArgumentError,
                    "cannot resolve provider-local schema ref \#{inspect({module, type})}: expected \#{inspect(module)} to export __schema__/1 or schema/0"
          end

        wrap_resolved_schema(resolved, top_level?)
      end

      defp resolve_type_spec({:union, types}, type_schemas, top_level?) do
        types =
          types
          |> Enum.map(&resolve_type_spec(&1, type_schemas, false))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(&specificity_score/1, :desc)

        case types do
          [] -> nil
          [single] when top_level? -> single
          [single] -> single
          many -> {:union, many}
        end
      end

      defp resolve_type_spec([inner], type_schemas, _top_level?) do
        case resolve_type_spec(inner, type_schemas, false) do
          nil -> nil
          resolved -> {:array, resolved}
        end
      end

      defp resolve_type_spec({:array, inner}, type_schemas, _top_level?) do
        case resolve_type_spec(inner, type_schemas, false) do
          nil -> nil
          resolved -> {:array, resolved}
        end
      end

      defp resolve_type_spec({:nullable, inner}, type_schemas, _top_level?) do
        case resolve_type_spec(inner, type_schemas, false) do
          nil -> nil
          resolved -> {:nullable, resolved}
        end
      end

      defp resolve_type_spec({:map, key_type, value_type}, type_schemas, _top_level?) do
        {:map, resolve_type_spec(key_type, type_schemas, false),
         resolve_type_spec(value_type, type_schemas, false)}
      end

      defp resolve_type_spec({:tuple, types}, type_schemas, _top_level?) do
        {:tuple, Enum.map(types, &resolve_type_spec(&1, type_schemas, false))}
      end

      defp resolve_type_spec({:object, %Schema{} = schema}, _type_schemas, top_level?) do
        wrap_resolved_schema(schema, top_level?)
      end

      defp resolve_type_spec(%Schema{} = schema, _type_schemas, top_level?) do
        wrap_resolved_schema(schema, top_level?)
      end

      defp resolve_type_spec(other, _type_schemas, _top_level?), do: other

      defp wrap_resolved_schema(nil, _top_level?), do: nil
      defp wrap_resolved_schema(%Schema{} = schema, true), do: schema
      defp wrap_resolved_schema(%Schema{} = schema, false), do: {:object, schema}
      defp wrap_resolved_schema(other, _top_level?), do: other

      defp to_runtime_type({module, type_name})
           when is_atom(module) and is_atom(type_name) and module not in @non_module_ref_heads do
        {module, type_name}
        |> resolve_type_spec(%{}, true)
        |> wrap_resolved_schema(false)
      end

      defp to_runtime_type([inner]), do: {:array, to_runtime_type(inner)}
      defp to_runtime_type({:array, inner}), do: {:array, to_runtime_type(inner)}
      defp to_runtime_type({:union, types}), do: {:union, Enum.map(types, &to_runtime_type/1)}
      defp to_runtime_type({:nullable, inner}), do: {:nullable, to_runtime_type(inner)}
      defp to_runtime_type({:tuple, types}), do: {:tuple, Enum.map(types, &to_runtime_type/1)}

      defp to_runtime_type({:map, key_type, value_type}) do
        {:map, to_runtime_type(key_type), to_runtime_type(value_type)}
      end

      defp to_runtime_type({:enum, literals}) when is_list(literals) do
        {:union, Enum.map(literals, &{:literal, &1})}
      end

      defp to_runtime_type({:const, literal}), do: {:literal, literal}
      defp to_runtime_type({:string, "date"}), do: :date
      defp to_runtime_type({:string, "date-time"}), do: :datetime
      defp to_runtime_type({:string, "time"}), do: :string
      defp to_runtime_type({:string, "uuid"}), do: :uuid
      defp to_runtime_type({:string, _format}), do: :string
      defp to_runtime_type({:integer, _format}), do: :integer
      defp to_runtime_type({:number, _format}), do: {:union, [:integer, :float]}
      defp to_runtime_type({:boolean, _format}), do: :boolean
      defp to_runtime_type(:number), do: {:union, [:integer, :float]}
      defp to_runtime_type(:unknown), do: :any
      defp to_runtime_type(other), do: other

      defp invoke_module_decode(module, type, data) do
        ensure_module_loaded!(module)

        cond do
          function_exported?(module, :decode, 2) ->
            module.decode(data, type)

          function_exported?(module, :decode, 1) and type == :t ->
            module.decode(data)

          true ->
            if function_exported?(module, :__schema__, 1) or
                 (function_exported?(module, :schema, 0) and type == :t) do
              decode_module_type(module, type, data)
            else
              raise ArgumentError,
                    "cannot decode provider-local schema ref \#{inspect({module, type})}: expected \#{inspect(module)} to export decode/2, decode/1, __schema__/1, or schema/0"
            end
        end
      end

      defp ensure_module_loaded!(module) when is_atom(module) do
        case Code.ensure_loaded(module) do
          {:module, _loaded} ->
            :ok

          {:error, _reason} ->
            raise ArgumentError,
                  "cannot resolve provider-local schema ref: module \#{inspect(module)} is not available"
        end
      end
    end
    """

    rendered_file(provider_ir.artifact_plan.generated_code_dir, ["runtime_schema"], source)
  end

  defp render_client_file(provider_ir) do
    source = """
    defmodule #{provider_client_module_source(provider_ir.provider.base_module)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} client facade over `#{inspect(provider_ir.provider.client_module)}`.
      \"\"\"

      @spec new(keyword()) :: #{inspect(provider_ir.provider.client_module)}.t()
      def new(opts \\\\ []) when is_list(opts) do
        #{inspect(provider_ir.provider.client_module)}.new(opts)
      end
    end
    """

    rendered_file(provider_ir.artifact_plan.generated_code_dir, ["client"], source)
  end

  defp render_operation_file(provider_ir, module_name, operations, schemas) do
    functions =
      operations
      |> Enum.map_join("\n\n", fn operation ->
        render_operation_function(provider_ir, operation)
      end)

    schema_helpers = render_schema_helpers(provider_ir.provider.base_module, module_name, schemas)
    extension_use = render_module_extension_use(module_name)

    runtime_schema_alias =
      maybe_render_schema_runtime_alias(schemas, provider_ir.provider.base_module)

    openapi_client_alias =
      if operations == [] do
        ""
      else
        "  alias Pristine.SDK.OpenAPI.Client, as: OpenAPIClient\n\n"
      end

    request_opts_helper =
      if operations == [] do
        ""
      else
        """
          @spec normalize_request_opts!(list()) :: keyword()
          defp normalize_request_opts!(opts) when is_list(opts) do
            if Keyword.keyword?(opts) do
              opts
            else
              raise ArgumentError, "request opts must be a keyword list"
            end
          end
        """
      end

    source = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} operations for #{module_segment_label(module_name)}.
      \"\"\"

    #{extension_use}#{runtime_schema_alias}#{openapi_client_alias}#{functions}
    #{request_opts_helper}
    #{schema_helpers}
    end
    """

    rendered_file(
      provider_ir.artifact_plan.generated_code_dir,
      module_relative_segments(module_name, provider_ir.provider.base_module),
      source
    )
  end

  defp render_schema_file(provider_ir, module_name, schemas) do
    {struct_source, type_specs} = render_struct_and_type_specs(module_name, schemas)
    schema_helpers = render_schema_helpers(provider_ir.provider.base_module, module_name, schemas)
    runtime_schema_alias = render_schema_runtime_alias(provider_ir.provider.base_module)

    source = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} type for #{module_segment_label(module_name)}.
      \"\"\"

    #{runtime_schema_alias}#{struct_source}
    #{type_specs}
    #{schema_helpers}
    end
    """

    rendered_file(
      provider_ir.artifact_plan.generated_code_dir,
      ["schemas" | module_relative_segments(module_name, provider_ir.provider.base_module)],
      source
    )
  end

  defp render_operation_function(provider_ir, operation) do
    partition_attribute = "@#{operation.function}_partition_spec"
    auth_policy = find_policy(provider_ir.auth_policies, operation.auth_policy_id)
    client_module = provider_ir.provider.client_module

    pagination_policy =
      find_policy(provider_ir.pagination_policies, operation.pagination_policy_id)

    stream_wrapper =
      if pagination_policy do
        """

          @spec stream_#{operation.function}(term(), map(), keyword()) :: Enumerable.t()
          def stream_#{operation.function}(client, params \\\\ %{}, opts \\\\ [])
              when is_map(params) and is_list(opts) do
            opts = normalize_request_opts!(opts)

            Stream.resource(
              fn -> build_#{operation.function}_request(client, params, opts) end,
              fn
                nil ->
                  {:halt, nil}

                request when is_map(request) ->
                  wrapped_request =
                    update_in(request[:opts], fn request_opts ->
                      Keyword.put(request_opts || [], :response, :wrapped)
                    end)

                  case #{inspect(client_module)}.execute_generated_request(client, wrapped_request) do
                    {:ok, response} ->
                      items = List.wrap(OpenAPIClient.items(request, response))
                      {items, OpenAPIClient.next_page_request(request, response)}

                    {:error, reason} ->
                      raise "pagination failed: " <> inspect(reason)
                  end
              end,
              fn _state -> :ok end
            )
          end
        """
      else
        ""
      end

    """
      #{partition_attribute} #{inspect(partition_spec(operation, auth_policy), pretty: true)}

      @doc #{render_string_literal(operation_doc(operation))}
      @spec #{operation.function}(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
      def #{operation.function}(client, params \\\\ %{}, opts \\\\ [])
          when is_map(params) and is_list(opts) do
        opts = normalize_request_opts!(opts)
        request = build_#{operation.function}_request(client, params, opts)
        #{inspect(client_module)}.execute_generated_request(client, request)
      end#{stream_wrapper}

      defp build_#{operation.function}_request(client, params, opts)
           when is_map(params) and is_list(opts) do
        _ = client
        partition = OpenAPIClient.partition(params, #{partition_attribute})

        %{
          id: #{inspect(operation.id)},
          args: params,
          call: {__MODULE__, #{inspect(operation.function)}},
          opts: opts,
          method: #{inspect(operation.method)},
          path_template: #{inspect(operation.path_template)},
          path_params: partition.path_params,
          query: partition.query,
          headers: partition.headers,
          body: partition.body,
          form_data: partition.form_data,
          request_schema: #{render_term(operation.request_schema)},
          response_schemas: #{render_term(operation.response_schemas)},
          auth: #{render_runtime_auth(auth_policy)},
          resource: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :resource))},
          retry: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :retry_group))},
          circuit_breaker: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :circuit_breaker))},
          rate_limit: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :rate_limit_group))},
          telemetry: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :telemetry_event))},
          timeout: #{render_term(Map.get(runtime_metadata(operation.runtime_metadata), :timeout_ms))},
          pagination: #{render_term(runtime_pagination(pagination_policy))}
        }
      end
    """
  end

  defp render_struct_and_type_specs(module_name, schemas) do
    default_schema = Enum.find(schemas, &(&1.type_name == :t))

    struct_source =
      case default_schema do
        %ProviderIR.Schema{fields: fields} when fields != [] ->
          fields = Enum.map(fields, &Identifier.atom_source!(&1.name, "schema field"))
          required_fields = required_field_sources(default_schema.fields)

          """
          @enforce_keys [#{Enum.join(required_fields, ", ")}]
          defstruct [#{Enum.join(fields, ", ")}]
          """

        _other ->
          ""
      end

    type_specs =
      schemas
      |> Enum.map_join("\n\n", fn schema ->
        render_schema_type_spec(module_name, schema)
      end)

    {struct_source, type_specs}
  end

  defp render_schema_type_spec(module_name, %ProviderIR.Schema{
         type_name: type_name,
         fields: fields
       }) do
    rendered_type_name = rendered_typespec_name(type_name)

    type_body =
      case {type_name, fields} do
        {:t, [_ | _]} ->
          field_types =
            fields
            |> Enum.map_join(",\n", fn field ->
              "        #{Identifier.atom_key_source!(field.name, "schema field")}: #{render_typespec(field.type, module_name)}"
            end)

          "%__MODULE__{\n#{field_types}\n      }"

        {_type_name, [_ | _]} ->
          "map()"

        _other ->
          "term()"
      end

    "@type #{rendered_type_name} :: #{type_body}"
  end

  defp render_schema_helpers(_base_module, _module_name, []), do: ""

  defp render_schema_helpers(base_module, _module_name, schemas) do
    default_type_name = default_type_name(schemas)
    _runtime_schema_module = provider_runtime_schema_module_source(base_module)

    fields_clauses =
      schemas
      |> Enum.map_join("\n\n", fn schema ->
        """
          def __fields__(#{inspect(schema.type_name)}) do
            [
        #{render_fields_keyword(schema.fields)}
            ]
          end
        """
      end)

    openapi_fields_clauses =
      schemas
      |> Enum.map_join("\n\n", fn schema ->
        """
          def __openapi_fields__(#{inspect(schema.type_name)}) do
            #{render_term(schema.fields)}
          end
        """
      end)

    """
      @doc false
      @spec __fields__(atom()) :: keyword()
      def __fields__(type \\\\ #{inspect(default_type_name)})

    #{fields_clauses}

      @doc false
      @spec __openapi_fields__(atom()) :: [map()]
      def __openapi_fields__(type \\\\ #{inspect(default_type_name)})

    #{openapi_fields_clauses}

      @doc false
      @spec __schema__(atom()) :: Sinter.Schema.t()
      def __schema__(type \\\\ #{inspect(default_type_name)}) when is_atom(type) do
        RuntimeSchema.build_schema(__openapi_fields__(type))
      end

      @doc false
      @spec decode(map(), atom()) :: {:ok, term()} | {:error, term()}
      def decode(data, type \\\\ #{inspect(default_type_name)})

      def decode(data, type) when is_map(data) and is_atom(type) do
        RuntimeSchema.decode_module_type(__MODULE__, type, data)
      end
    """
  end

  defp render_fields_keyword(fields) do
    fields
    |> Enum.map_join(",\n", fn field ->
      "      #{Identifier.atom_key_source!(field.name, "schema field")}: #{render_term(field.type)}"
    end)
  end

  defp rendered_file(generated_code_dir, segments, source) do
    relative_path =
      generated_code_dir
      |> Path.join(module_segments_to_path(segments))

    %RenderedFile{
      kind: :code,
      relative_path: relative_path,
      contents: format_source!(source)
    }
  end

  defp module_segments_to_path(segments) do
    segments
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    |> Kernel.<>(".ex")
  end

  defp provider_client_module_source(base_module),
    do: generated_module_source(base_module, ["Client"])

  defp provider_runtime_schema_module_source(base_module),
    do: generated_module_source(base_module, ["RuntimeSchema"])

  defp generated_module_source(base_module, suffix_segments) do
    Enum.join([inspect(base_module), "Generated" | suffix_segments], ".")
  end

  defp module_relative_segments(module_name, base_module) do
    module_segments = Module.split(module_name)
    base_segments = Module.split(base_module)
    generated_base_segments = base_segments ++ ["Generated"]

    case module_segments do
      ^base_segments ->
        [List.last(module_segments)]

      _other ->
        relative_segments(module_segments, generated_base_segments) ||
          relative_segments(module_segments, base_segments) ||
          module_segments
    end
  end

  defp module_segment_label(module_name) do
    module_name
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
  end

  defp provider_label(%ProviderIR{provider: provider}) do
    provider.package_name
    |> String.split("_")
    |> Enum.map_join(" ", fn
      "api" -> "API"
      segment -> Macro.camelize(segment)
    end)
  end

  defp partition_spec(operation, auth_policy) do
    base = %{
      path: Enum.map(operation.path_params, &{&1.name, &1.key}),
      query: Enum.map(operation.query_params, &{&1.name, &1.key}),
      headers: Enum.map(operation.header_params, &{&1.name, &1.key}),
      body: operation.body,
      form_data: operation.form_data
    }

    case auth_policy do
      %ProviderIR.AuthPolicy{mode: mode, override_source: %{key: key}}
      when mode in [:request_override, :request_override_optional] and is_atom(key) ->
        Map.put(base, :auth, {Atom.to_string(key), key})

      %ProviderIR.AuthPolicy{mode: mode, override_source: %{key: key}}
      when mode in [:request_override, :request_override_optional] and is_binary(key) ->
        raise ArgumentError,
              "auth override key must use a source-owned atom, got binary key #{inspect(key)}"

      %ProviderIR.AuthPolicy{mode: mode, override_source: %{mode: :key, key: key}}
      when mode in [:request_override, :request_override_optional] ->
        Map.put(base, :auth, %{mode: :key, key: key})

      %ProviderIR.AuthPolicy{mode: mode, override_source: %{mode: :keys, keys: keys}}
      when mode in [:request_override, :request_override_optional] ->
        Map.put(base, :auth, %{mode: :keys, keys: keys})

      _other ->
        base
    end
  end

  defp render_runtime_auth(nil) do
    "%{use_client_default?: true, override: nil, security_schemes: []}"
  end

  defp render_runtime_auth(%ProviderIR.AuthPolicy{} = auth_policy) do
    override =
      if auth_policy.mode in [:request_override, :request_override_optional] do
        "partition.auth"
      else
        "nil"
      end

    use_client_default? =
      auth_policy.mode in [:use_client_default, :request_override_optional]

    "%{use_client_default?: #{use_client_default?}, " <>
      "override: #{override}, security_schemes: #{inspect(auth_policy.security_schemes)}}"
  end

  defp runtime_metadata(runtime_metadata) do
    %{
      resource: Map.get(runtime_metadata, :resource),
      retry_group: Map.get(runtime_metadata, :retry_group),
      circuit_breaker: Map.get(runtime_metadata, :circuit_breaker),
      rate_limit_group: Map.get(runtime_metadata, :rate_limit_group),
      telemetry_event: Map.get(runtime_metadata, :telemetry_event),
      timeout_ms: Map.get(runtime_metadata, :timeout_ms)
    }
  end

  defp runtime_pagination(nil), do: nil

  defp runtime_pagination(%ProviderIR.PaginationPolicy{} = pagination_policy) do
    %{
      strategy: pagination_policy.strategy,
      request_mapping: pagination_policy.request_mapping,
      response_mapping: pagination_policy.response_mapping,
      default_limit: pagination_policy.default_limit,
      items_path: pagination_policy.items_path
    }
  end

  defp render_term({:__block__, _, _} = quoted), do: Macro.to_string(quoted)

  defp render_term(term) do
    term
    |> Macro.escape()
    |> Macro.to_string()
  end

  defp find_policy(_policies, nil), do: nil
  defp find_policy(policies, policy_id), do: Enum.find(policies, &(&1.id == policy_id))

  defp render_typespec(:string, _module_name), do: "String.t()"
  defp render_typespec(:integer, _module_name), do: "integer()"
  defp render_typespec(:number, _module_name), do: "number()"
  defp render_typespec(:boolean, _module_name), do: "boolean()"
  defp render_typespec(:map, _module_name), do: "map()"
  defp render_typespec(:null, _module_name), do: "nil"
  defp render_typespec(nil, _module_name), do: "term()"
  defp render_typespec({:string, "date"}, _module_name), do: "Date.t()"
  defp render_typespec({:string, "date-time"}, _module_name), do: "DateTime.t()"
  defp render_typespec({:string, "time"}, _module_name), do: "Time.t()"
  defp render_typespec({:string, _format}, _module_name), do: "String.t()"
  defp render_typespec({:const, value}, _module_name) when is_binary(value), do: "String.t()"
  defp render_typespec({:const, value}, _module_name), do: inspect(value)

  defp render_typespec({:enum, values}, _module_name) when is_list(values) do
    if values != [] and Enum.all?(values, &is_binary/1) do
      "String.t()"
    else
      Enum.map_join(values, " | ", &inspect/1)
    end
  end

  defp render_typespec({:union, types}, module_name) when is_list(types) do
    Enum.map_join(types, " | ", &render_typespec(&1, module_name))
  end

  defp render_typespec({:array, inner}, module_name),
    do: "[#{render_typespec(inner, module_name)}]"

  defp render_typespec([inner], module_name), do: "[#{render_typespec(inner, module_name)}]"

  defp render_typespec({module, type_name}, module_name) when module == module_name do
    "#{rendered_typespec_name(type_name)}()"
  end

  defp render_typespec({module, type_name}, _module_name) do
    "#{inspect(module)}.#{rendered_typespec_name(type_name)}()"
  end

  defp render_typespec(_other, _module_name), do: "term()"

  defp relative_segments(module_segments, prefix_segments) do
    case Enum.split(module_segments, length(prefix_segments)) do
      {^prefix_segments, relative_segments} when relative_segments != [] ->
        relative_segments

      _other ->
        nil
    end
  end

  defp default_type_name(schemas) do
    type_names = Enum.map(schemas, & &1.type_name)

    cond do
      :t in type_names -> :t
      type_names != [] -> hd(type_names)
      true -> :t
    end
  end

  defp required_field_sources(fields) do
    fields
    |> Enum.filter(&Map.get(&1, :required, false))
    |> Enum.map(&Identifier.atom_source!(&1.name, "required schema field"))
  end

  defp operation_doc(operation) do
    cond do
      is_binary(operation.docs_metadata[:doc]) ->
        operation.docs_metadata[:doc]

      is_binary(operation.description) and operation.description != "" ->
        operation.description

      is_binary(operation.summary) and operation.summary != "" ->
        operation.summary

      true ->
        operation.id
    end
  end

  defp render_string_literal(value) when is_binary(value) do
    if String.graphemes(value) |> Enum.count(&(&1 == "\"")) > 3 do
      render_quote_heavy_string_literal(value)
    else
      inspect(value, limit: :infinity, printable_limit: :infinity)
    end
  end

  defp render_quote_heavy_string_literal(value) do
    cond do
      not String.contains?(value, ~S(""")) ->
        "(\n  ~S\"\"\"\n#{value}\n  \"\"\"\n  |> String.trim_leading(\"\\n\")\n  |> String.trim_trailing(\"\\n\")\n)"

      not String.contains?(value, "'''") ->
        "(\n  ~S'''\n#{value}\n  '''\n  |> String.trim_leading(\"\\n\")\n  |> String.trim_trailing(\"\\n\")\n)"

      true ->
        inspect(value, limit: :infinity, printable_limit: :infinity)
    end
  end

  defp rendered_typespec_name(:map), do: :t
  defp rendered_typespec_name(type_name), do: type_name

  defp render_module_extension_use(module_name) do
    _module_name = module_name
    ""
  end

  defp render_schema_runtime_alias(base_module) do
    "  alias #{provider_runtime_schema_module_source(base_module)}, as: RuntimeSchema\n\n"
  end

  defp maybe_render_schema_runtime_alias([], _base_module), do: ""

  defp maybe_render_schema_runtime_alias(_schemas, base_module),
    do: render_schema_runtime_alias(base_module)

  defp format_source!(source) do
    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end
end
