defmodule PristineCodegen.Render.ElixirSDK do
  @moduledoc """
  Shared Elixir SDK renderer that projects `PristineCodegen.ProviderIR` into
  generated provider client, operation, pagination, and type modules.
  """

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

    [client_file | operation_files ++ schema_files]
  end

  defp render_client_file(provider_ir) do
    default_headers =
      provider_ir.runtime_defaults.default_headers
      |> Map.put_new("user-agent", provider_ir.runtime_defaults.user_agent_prefix)

    source = """
    defmodule #{inspect(provider_client_module(provider_ir.provider.base_module))} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} client facade over `Pristine.Client`.
      \"\"\"

      @spec new(keyword()) :: Pristine.Client.t()
      def new(opts \\\\ []) when is_list(opts) do
        base_url = Keyword.get(opts, :base_url, #{inspect(provider_ir.runtime_defaults.base_url)})
        timeout_ms = Keyword.get(opts, :timeout_ms, #{integer_literal(provider_ir.runtime_defaults.timeout_ms)})

        default_headers =
          opts
          |> Keyword.get(:default_headers, %{})
          |> Enum.into(#{inspect(default_headers)})

        default_auth = Keyword.get(opts, :default_auth, [])

        Pristine.Client.new(
          base_url: base_url,
          default_headers: default_headers,
          default_auth: default_auth,
          timeout_ms: timeout_ms
        )
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

    schema_helpers = render_schema_helpers(module_name, schemas)
    extension_use = render_module_extension_use(module_name)

    source = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} operations for #{module_segment_label(module_name)}.
      \"\"\"

    #{extension_use}#{functions}
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
    schema_helpers = render_schema_helpers(module_name, schemas)

    source = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} type for #{module_segment_label(module_name)}.
      \"\"\"

    #{struct_source}
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

    pagination_policy =
      find_policy(provider_ir.pagination_policies, operation.pagination_policy_id)

    {runtime_client_var, runtime_client_source} = runtime_client_binding(provider_ir)

    stream_wrapper =
      if pagination_policy do
        """

          @spec stream_#{operation.function}(term(), map(), keyword()) :: Enumerable.t()
          def stream_#{operation.function}(client, params \\\\ %{}, opts \\\\ [])
              when is_map(params) and is_list(opts) do
            #{runtime_client_source}Stream.resource(
              fn -> build_#{operation.function}_operation(params) end,
              fn
                nil ->
                  {:halt, nil}

                %Pristine.Operation{} = operation ->
                  case Pristine.execute(#{runtime_client_var}, operation, opts) do
                    {:ok, response} ->
                      items = List.wrap(Pristine.Operation.items(operation, response))
                      {items, Pristine.Operation.next_page(operation, response)}

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
        #{runtime_client_source}operation = build_#{operation.function}_operation(params)
        Pristine.execute(#{runtime_client_var}, operation, opts)
      end#{stream_wrapper}

      defp build_#{operation.function}_operation(params) when is_map(params) do
        partition = Pristine.Operation.partition(params, #{partition_attribute})

        Pristine.Operation.new(%{
          id: #{inspect(operation.id)},
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
          runtime: #{render_term(runtime_metadata(operation.runtime_metadata))},
          pagination: #{render_term(runtime_pagination(pagination_policy))}
        })
      end
    """
  end

  defp render_struct_and_type_specs(module_name, schemas) do
    default_schema = Enum.find(schemas, &(&1.type_name == :t))

    struct_source =
      case default_schema do
        %ProviderIR.Schema{fields: fields} when fields != [] ->
          fields = Enum.map(fields, &String.to_atom(&1.name))
          required_fields = required_field_atoms(default_schema.fields)

          """
          @enforce_keys #{inspect(required_fields)}
          defstruct #{inspect(fields)}
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
              "        #{field.name}: #{render_typespec(field.type, module_name)}"
            end)

          "%__MODULE__{\n#{field_types}\n      }"

        {_type_name, [_ | _]} ->
          "map()"

        _other ->
          "term()"
      end

    "@type #{rendered_type_name} :: #{type_body}"
  end

  defp render_schema_helpers(_module_name, []), do: ""

  defp render_schema_helpers(module_name, schemas) do
    default_type_name = default_type_name(schemas)

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
        Pristine.Runtime.Schema.build_schema(__openapi_fields__(type))
      end

      @doc false
      @spec decode(map(), atom()) :: {:ok, term()} | {:error, term()}
      def decode(data, type \\\\ #{inspect(default_type_name)})

      def decode(data, type) when is_map(data) and is_atom(type) do
        Pristine.Runtime.Schema.decode_module_type(#{inspect(module_name)}, type, data)
      end
    """
  end

  defp render_fields_keyword(fields) do
    fields
    |> Enum.map_join(",\n", fn field ->
      "      #{String.to_atom(field.name)}: #{render_term(field.type)}"
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

  defp provider_client_module(base_module), do: Module.concat([base_module, Generated, Client])

  defp module_relative_segments(module_name, base_module) do
    module_segments = Module.split(module_name)
    base_segments = Module.split(base_module)
    generated_base_segments = base_segments ++ ["Generated"]

    case module_segments do
      ^base_segments ->
        [List.last(module_segments)]

      _other ->
        case Enum.split(module_segments, length(generated_base_segments)) do
          {^generated_base_segments, relative_segments} when relative_segments != [] ->
            relative_segments

          _other ->
            case Enum.split(module_segments, length(base_segments)) do
              {^base_segments, relative_segments} when relative_segments != [] ->
                relative_segments

              _other ->
                module_segments
            end
        end
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
      when mode in [:request_override, :request_override_optional] ->
        Map.put(base, :auth, {key, String.to_atom(key)})

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
      values
      |> Enum.map(&inspect/1)
      |> Enum.join(" | ")
    end
  end

  defp render_typespec({:union, types}, module_name) when is_list(types) do
    types
    |> Enum.map(&render_typespec(&1, module_name))
    |> Enum.join(" | ")
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

  defp default_type_name(schemas) do
    type_names = Enum.map(schemas, & &1.type_name)

    cond do
      :t in type_names -> :t
      type_names != [] -> hd(type_names)
      true -> :t
    end
  end

  defp required_field_atoms(fields) do
    fields
    |> Enum.filter(&Map.get(&1, :required, false))
    |> Enum.map(&String.to_atom(&1.name))
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
    inspect(value, limit: :infinity, printable_limit: :infinity)
  end

  defp rendered_typespec_name(:map), do: :t
  defp rendered_typespec_name(type_name), do: type_name

  defp render_module_extension_use(module_name) do
    helper_module = Module.concat([module_name, Helpers])

    if Code.ensure_loaded?(helper_module) do
      "  use #{inspect(helper_module)}\n\n"
    else
      ""
    end
  end

  defp runtime_client_binding(%ProviderIR{provider: %{client_module: nil}}), do: {"client", ""}

  defp runtime_client_binding(%ProviderIR{provider: %{client_module: client_module}}) do
    {"runtime_client",
     "runtime_client = #{inspect(client_module)}.pristine_client(client)\n        "}
  end

  defp format_source!(source) do
    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp integer_literal(nil), do: "nil"

  defp integer_literal(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?!$)/, "\\0_")
    |> String.reverse()
  end
end
