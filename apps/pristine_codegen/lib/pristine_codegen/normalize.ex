defmodule PristineCodegen.Normalize do
  @moduledoc false

  alias PristineCodegen.ProviderIR
  alias PristineCodegen.ProviderIR.Artifact
  alias PristineCodegen.ProviderIR.ArtifactPlan
  alias PristineCodegen.ProviderIR.AuthPolicy
  alias PristineCodegen.ProviderIR.DocsInventory
  alias PristineCodegen.ProviderIR.Fingerprints
  alias PristineCodegen.ProviderIR.Operation
  alias PristineCodegen.ProviderIR.PaginationPolicy
  alias PristineCodegen.ProviderIR.Provider
  alias PristineCodegen.ProviderIR.RuntimeDefaults
  alias PristineCodegen.ProviderIR.Schema

  @spec from_definition(map()) :: ProviderIR.t()
  def from_definition(definition) when is_map(definition) do
    provider = normalize_provider(Map.fetch!(definition, :provider))
    schemas = normalize_schemas(Map.get(definition, :schemas, []), provider.base_module)
    schema_modules_by_id = Map.new(schemas, &{&1.id, &1.module})

    %ProviderIR{
      provider: provider,
      runtime_defaults: normalize_runtime_defaults(Map.fetch!(definition, :runtime_defaults)),
      operations:
        normalize_operations(
          Map.get(definition, :operations, []),
          provider.base_module,
          schema_modules_by_id
        ),
      schemas: schemas,
      auth_policies: normalize_auth_policies(Map.get(definition, :auth_policies, [])),
      pagination_policies:
        normalize_pagination_policies(Map.get(definition, :pagination_policies, [])),
      docs_inventory: normalize_docs_inventory(Map.get(definition, :docs_inventory, %{})),
      artifact_plan: normalize_artifact_plan(Map.fetch!(definition, :artifact_plan)),
      fingerprints: normalize_fingerprints(Map.get(definition, :fingerprints, %{}))
    }
  end

  @spec attach_code_artifacts(ProviderIR.t(), [PristineCodegen.RenderedFile.t()]) ::
          ProviderIR.t()
  def attach_code_artifacts(%ProviderIR{} = provider_ir, rendered_files)
      when is_list(rendered_files) do
    code_artifacts =
      rendered_files
      |> Enum.map(fn rendered_file ->
        %Artifact{
          id: code_artifact_id(rendered_file.relative_path),
          path: rendered_file.relative_path,
          kind: :code
        }
      end)
      |> Enum.sort_by(& &1.path)

    artifacts =
      (code_artifacts ++ provider_ir.artifact_plan.artifacts)
      |> Enum.uniq_by(& &1.path)

    artifact_plan = %{provider_ir.artifact_plan | artifacts: artifacts}
    %{provider_ir | artifact_plan: artifact_plan}
  end

  defp normalize_provider(provider) do
    %Provider{
      id: Map.fetch!(provider, :id),
      base_module: Map.fetch!(provider, :base_module),
      client_module: Map.get(provider, :client_module),
      package_app: Map.fetch!(provider, :package_app),
      package_name: Map.fetch!(provider, :package_name),
      source_strategy: Map.fetch!(provider, :source_strategy)
    }
  end

  defp normalize_runtime_defaults(runtime_defaults) do
    %RuntimeDefaults{
      base_url: Map.get(runtime_defaults, :base_url),
      default_headers: stringify_map(Map.get(runtime_defaults, :default_headers, %{})),
      user_agent_prefix: Map.get(runtime_defaults, :user_agent_prefix),
      timeout_ms: Map.get(runtime_defaults, :timeout_ms),
      retry_defaults: Map.get(runtime_defaults, :retry_defaults, %{}),
      serializer: Map.get(runtime_defaults, :serializer),
      typed_responses_default: Map.get(runtime_defaults, :typed_responses_default, false)
    }
  end

  defp normalize_schemas(schemas, base_module) do
    schemas
    |> Enum.map(fn schema ->
      %Schema{
        id: Map.fetch!(schema, :id),
        module: normalize_generated_module(base_module, Map.fetch!(schema, :module)),
        type_name: normalize_function(Map.get(schema, :type_name, :t)),
        kind: Map.fetch!(schema, :kind),
        fields:
          schema
          |> Map.get(:fields, [])
          |> Enum.map(&normalize_field/1),
        source_refs:
          schema
          |> Map.get(:source_refs, [])
          |> Enum.map(&normalize_map/1)
      }
    end)
    |> Enum.sort_by(&{&1.module, &1.type_name, &1.id})
  end

  defp normalize_operations(operations, base_module, schema_modules_by_id) do
    operations
    |> Enum.map(fn operation ->
      %Operation{
        id: Map.fetch!(operation, :id),
        module: normalize_generated_module(base_module, Map.fetch!(operation, :module)),
        function: normalize_function(Map.fetch!(operation, :function)),
        method: normalize_method(Map.fetch!(operation, :method)),
        path_template: Map.fetch!(operation, :path_template),
        summary: Map.get(operation, :summary),
        description: Map.get(operation, :description),
        path_params: normalize_params(Map.get(operation, :path_params, [])),
        query_params: normalize_params(Map.get(operation, :query_params, [])),
        header_params: normalize_params(Map.get(operation, :header_params, [])),
        body: normalize_payload_spec(Map.get(operation, :body, %{mode: :none})),
        form_data: normalize_payload_spec(Map.get(operation, :form_data, %{mode: :none})),
        request_schema:
          normalize_schema_ref(Map.get(operation, :request_schema), schema_modules_by_id),
        response_schemas:
          normalize_response_schemas(
            Map.get(operation, :response_schemas, %{}),
            schema_modules_by_id
          ),
        auth_policy_id: Map.get(operation, :auth_policy_id),
        pagination_policy_id: Map.get(operation, :pagination_policy_id),
        runtime_metadata: normalize_map(Map.get(operation, :runtime_metadata, %{})),
        docs_metadata: normalize_map(Map.get(operation, :docs_metadata, %{examples: []}))
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_auth_policies(auth_policies) do
    auth_policies
    |> Enum.map(fn auth_policy ->
      %AuthPolicy{
        id: Map.fetch!(auth_policy, :id),
        mode: Map.fetch!(auth_policy, :mode),
        security_schemes: Map.get(auth_policy, :security_schemes, []),
        override_source: normalize_map(Map.get(auth_policy, :override_source)),
        strategy_label: Map.get(auth_policy, :strategy_label)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_pagination_policies(pagination_policies) do
    pagination_policies
    |> Enum.map(fn pagination_policy ->
      %PaginationPolicy{
        id: Map.fetch!(pagination_policy, :id),
        strategy: Map.fetch!(pagination_policy, :strategy),
        request_mapping: normalize_map(Map.get(pagination_policy, :request_mapping, %{})),
        response_mapping: normalize_map(Map.get(pagination_policy, :response_mapping, %{})),
        default_limit: Map.get(pagination_policy, :default_limit),
        items_path: Map.get(pagination_policy, :items_path)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_docs_inventory(docs_inventory) do
    %DocsInventory{
      guides: Enum.map(Map.get(docs_inventory, :guides, []), &normalize_map/1),
      examples: Enum.map(Map.get(docs_inventory, :examples, []), &normalize_map/1),
      operations:
        docs_inventory
        |> Map.get(:operations, %{})
        |> Enum.map(fn {operation_id, metadata} ->
          {to_string(operation_id), normalize_map(metadata)}
        end)
        |> Map.new()
    }
  end

  defp normalize_artifact_plan(artifact_plan) do
    %ArtifactPlan{
      generated_code_dir: Map.fetch!(artifact_plan, :generated_code_dir),
      artifacts:
        artifact_plan
        |> Map.get(:artifacts, [])
        |> Enum.map(fn artifact ->
          %Artifact{
            id: Map.fetch!(artifact, :id),
            path: Map.fetch!(artifact, :path),
            kind: Map.get(artifact, :kind, artifact_kind(Map.fetch!(artifact, :path)))
          }
        end),
      forbidden_paths:
        artifact_plan
        |> Map.get(:forbidden_paths, [])
    }
  end

  defp normalize_fingerprints(fingerprints) do
    %Fingerprints{
      sources:
        fingerprints
        |> Map.get(:sources, [])
        |> Enum.map(&normalize_map/1)
        |> Enum.sort_by(&{Map.get(&1, :path), Map.get(&1, :kind)}),
      generation: normalize_map(Map.get(fingerprints, :generation, %{}))
    }
  end

  defp normalize_field(field) do
    field
    |> normalize_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
  end

  defp normalize_params(params) do
    params
    |> Enum.map(fn param ->
      %{
        key: normalize_param_key(Map.get(param, :key, Map.fetch!(param, :name))),
        name: Map.fetch!(param, :name),
        required: Map.get(param, :required, false)
      }
    end)
  end

  defp normalize_payload_spec(%{mode: :key, key: key}) do
    %{mode: :key, key: normalize_key_spec(key)}
  end

  defp normalize_payload_spec(%{mode: :keys, keys: keys}) do
    %{mode: :keys, keys: Enum.map(keys, &normalize_key_spec/1)}
  end

  defp normalize_payload_spec(%{mode: mode}) when mode in [:none, :remaining] do
    %{mode: mode}
  end

  defp normalize_payload_spec(nil), do: %{mode: :none}
  defp normalize_payload_spec(payload_spec), do: payload_spec

  defp normalize_response_schemas(response_schemas, schema_modules_by_id) do
    response_schemas
    |> Enum.map(fn {status, schema} ->
      {normalize_status_key(status), normalize_response_schema(schema, schema_modules_by_id)}
    end)
    |> Map.new()
  end

  defp normalize_response_schema(nil, _schema_modules_by_id), do: nil

  defp normalize_response_schema(schema, schema_modules_by_id) when is_map(schema) do
    schema
    |> normalize_map()
    |> Enum.map(fn
      {:schema, schema_ref} -> {:schema, normalize_schema_ref(schema_ref, schema_modules_by_id)}
      {key, value} -> {key, normalize_map(value)}
    end)
    |> Map.new()
  end

  defp normalize_response_schema(schema, schema_modules_by_id) do
    normalize_schema_ref(schema, schema_modules_by_id)
  end

  defp normalize_schema_ref(schema_ref, schema_modules_by_id) when is_binary(schema_ref) do
    Map.get(schema_modules_by_id, schema_ref, schema_ref)
  end

  defp normalize_schema_ref(schema_ref, schema_modules_by_id) when is_atom(schema_ref) do
    Map.get(schema_modules_by_id, Atom.to_string(schema_ref), schema_ref)
  end

  defp normalize_schema_ref(schema_ref, _schema_modules_by_id), do: normalize_map(schema_ref)

  defp normalize_key_spec({string_key, atom_key})
       when is_binary(string_key) and is_atom(atom_key) do
    {string_key, atom_key}
  end

  defp normalize_key_spec(atom_key) when is_atom(atom_key) do
    {Atom.to_string(atom_key), atom_key}
  end

  defp normalize_key_spec(string_key) when is_binary(string_key) do
    {string_key, String.to_atom(string_key)}
  end

  defp normalize_generated_module(_base_module, module) when is_atom(module), do: module

  defp normalize_generated_module(base_module, module) when is_binary(module) do
    segments =
      module
      |> String.split(".")
      |> Enum.reject(&(&1 == ""))

    Module.concat([base_module, Generated | Enum.map(segments, &String.to_atom/1)])
  end

  defp normalize_function(function) when is_atom(function), do: function
  defp normalize_function(function) when is_binary(function), do: String.to_atom(function)

  defp normalize_method(method) when is_atom(method), do: method
  defp normalize_method(method) when is_binary(method), do: String.to_atom(method)

  defp normalize_param_key(key) when is_atom(key), do: key
  defp normalize_param_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_param_key(key), do: key

  defp normalize_status_key(status) when is_integer(status), do: status
  defp normalize_status_key(status) when is_binary(status), do: String.to_integer(status)
  defp normalize_status_key(status), do: status

  defp normalize_map(nil), do: nil

  defp normalize_map(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {normalize_map_key(key), normalize_map(value)} end)
  end

  defp normalize_map(list) when is_list(list), do: Enum.map(list, &normalize_map/1)
  defp normalize_map(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map(_map), do: %{}

  defp normalize_map_key(key) when is_binary(key), do: key
  defp normalize_map_key(key), do: key

  defp artifact_kind(path) do
    case Path.extname(path) do
      ".ex" -> :code
      _other -> :artifact
    end
  end

  defp code_artifact_id(relative_path) do
    relative_path
    |> Path.rootname()
    |> String.replace("/", "_")
    |> String.to_atom()
  end
end
