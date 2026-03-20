defmodule PristineCodegen.Render.ElixirSDK do
  @moduledoc """
  Shared Elixir SDK renderer that projects `PristineCodegen.ProviderIR` into
  generated provider client, operation, pagination, and type modules.
  """

  alias PristineCodegen.ProviderIR
  alias PristineCodegen.RenderedFile

  @spec render(ProviderIR.t()) :: [RenderedFile.t()]
  def render(%ProviderIR{} = provider_ir) do
    client_file = render_client_file(provider_ir)

    operation_files =
      provider_ir.operations
      |> Enum.group_by(& &1.module)
      |> Enum.map(fn {module_name, operations} ->
        render_operation_file(provider_ir, module_name, Enum.sort_by(operations, & &1.id))
      end)

    schema_files = Enum.map(provider_ir.schemas, &render_schema_file(provider_ir, &1))

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

  defp render_operation_file(provider_ir, module_name, operations) do
    functions =
      operations
      |> Enum.map_join("\n\n", fn operation ->
        render_operation_function(provider_ir, operation)
      end)

    source = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} operations for #{module_segment_label(module_name)}.
      \"\"\"

    #{functions}
    end
    """

    relative_segments =
      module_name
      |> module_relative_segments(provider_ir.provider.base_module)

    rendered_file(provider_ir.artifact_plan.generated_code_dir, relative_segments, source)
  end

  defp render_operation_function(provider_ir, operation) do
    partition_attribute = "@#{operation.function}_partition_spec"
    auth_policy = find_policy(provider_ir.auth_policies, operation.auth_policy_id)

    pagination_policy =
      find_policy(provider_ir.pagination_policies, operation.pagination_policy_id)

    stream_wrapper =
      if pagination_policy do
        """

          @spec stream_#{operation.function}(Pristine.Client.t(), map(), keyword()) :: Enumerable.t()
          def stream_#{operation.function}(%Pristine.Client{} = client, params \\\\ %{}, opts \\\\ [])
              when is_map(params) and is_list(opts) do
            Stream.resource(
              fn -> build_#{operation.function}_operation(params) end,
              fn
                nil ->
                  {:halt, nil}

                %Pristine.Operation{} = operation ->
                  case Pristine.execute(client, operation, opts) do
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

      @spec #{operation.function}(Pristine.Client.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
      def #{operation.function}(%Pristine.Client{} = client, params \\\\ %{}, opts \\\\ [])
          when is_map(params) and is_list(opts) do
        operation = build_#{operation.function}_operation(params)
        Pristine.execute(client, operation, opts)
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

  defp render_schema_file(provider_ir, schema) do
    fields = Enum.map(schema.fields, &String.to_atom(&1.name))

    field_types =
      schema.fields
      |> Enum.map_join(",\n", fn field ->
        "          #{field.name}: #{type_literal(field.type)}()"
      end)

    source = """
    defmodule #{inspect(schema.module)} do
      @moduledoc \"\"\"
      Generated #{provider_label(provider_ir)} type for #{String.downcase(List.last(Module.split(schema.module)))}.
      \"\"\"

      @enforce_keys #{inspect(fields)}
      defstruct #{inspect(fields)}

      @type t :: %__MODULE__{
    #{field_types}
            }
    end
    """

    relative_segments = module_relative_segments(schema.module, provider_ir.provider.base_module)
    rendered_file(provider_ir.artifact_plan.generated_code_dir, relative_segments, source)
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
    prefix = Module.split(base_module) ++ ["Generated"]
    Module.split(module_name) |> Enum.drop(length(prefix))
  end

  defp module_segment_label(module_name) do
    module_name
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
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
    base =
      %{
        path: Enum.map(operation.path_params, &{&1.name, &1.key}),
        query: Enum.map(operation.query_params, &{&1.name, &1.key}),
        headers: Enum.map(operation.header_params, &{&1.name, &1.key}),
        body: operation.body,
        form_data: operation.form_data
      }

    case auth_policy do
      %ProviderIR.AuthPolicy{mode: :request_override, override_source: %{key: key}} ->
        Map.put(base, :auth, {key, String.to_atom(key)})

      _other ->
        base
    end
  end

  defp render_runtime_auth(nil) do
    "%{use_client_default?: true, override: nil, security_schemes: []}"
  end

  defp render_runtime_auth(%ProviderIR.AuthPolicy{} = auth_policy) do
    override =
      if auth_policy.mode == :request_override do
        "partition.auth"
      else
        "nil"
      end

    "%{use_client_default?: #{auth_policy.mode == :use_client_default}, " <>
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

  defp type_literal(:string), do: "String.t"
  defp type_literal(:integer), do: "integer"
  defp type_literal(:boolean), do: "boolean"
  defp type_literal(_other), do: "term"

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
