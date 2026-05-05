defmodule PristineCodegen.ProviderIR do
  @moduledoc """
  Canonical build-time contract rendered by the shared provider compiler.
  """

  defmodule Provider do
    @moduledoc """
    Provider identity and naming contract for one generated SDK.
    """

    @type t :: %__MODULE__{
            id: atom() | String.t(),
            base_module: module(),
            client_module: module() | nil,
            package_app: atom(),
            package_name: String.t(),
            source_strategy: atom()
          }

    @enforce_keys [:id, :base_module, :package_app, :package_name, :source_strategy]
    defstruct [:id, :base_module, :client_module, :package_app, :package_name, :source_strategy]
  end

  defmodule RuntimeDefaults do
    @moduledoc """
    Provider-wide runtime defaults applied to generated clients and operations.
    """

    @type t :: %__MODULE__{
            base_url: String.t() | nil,
            default_headers: map(),
            user_agent_prefix: String.t() | nil,
            timeout_ms: non_neg_integer() | nil,
            retry_defaults: map(),
            serializer: term(),
            typed_responses_default: boolean()
          }

    @enforce_keys [
      :base_url,
      :default_headers,
      :user_agent_prefix,
      :timeout_ms,
      :retry_defaults,
      :serializer,
      :typed_responses_default
    ]
    defstruct [
      :base_url,
      :default_headers,
      :user_agent_prefix,
      :timeout_ms,
      :retry_defaults,
      :serializer,
      :typed_responses_default
    ]
  end

  defmodule Operation do
    @moduledoc """
    Canonical operation inventory entry rendered into `Pristine.Operation`.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            module: module(),
            function: atom(),
            method: atom(),
            path_template: String.t(),
            summary: String.t() | nil,
            description: String.t() | nil,
            path_params: [map()],
            query_params: [map()],
            header_params: [map()],
            body: map(),
            form_data: map(),
            request_schema: term(),
            response_schemas: map(),
            auth_policy_id: String.t() | nil,
            pagination_policy_id: String.t() | nil,
            runtime_metadata: map(),
            docs_metadata: map()
          }

    @enforce_keys [
      :id,
      :module,
      :function,
      :method,
      :path_template,
      :summary,
      :description,
      :path_params,
      :query_params,
      :header_params,
      :body,
      :form_data,
      :request_schema,
      :response_schemas,
      :auth_policy_id,
      :pagination_policy_id,
      :runtime_metadata,
      :docs_metadata
    ]
    defstruct [
      :id,
      :module,
      :function,
      :method,
      :path_template,
      :summary,
      :description,
      :path_params,
      :query_params,
      :header_params,
      :body,
      :form_data,
      :request_schema,
      :response_schemas,
      :auth_policy_id,
      :pagination_policy_id,
      :runtime_metadata,
      :docs_metadata
    ]
  end

  defmodule AuthPolicy do
    @moduledoc """
    Canonical auth-policy entry referenced by operations.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            mode: atom(),
            security_schemes: [String.t()],
            override_source: map() | nil,
            strategy_label: String.t() | nil
          }

    @enforce_keys [:id, :mode, :security_schemes, :override_source, :strategy_label]
    defstruct [:id, :mode, :security_schemes, :override_source, :strategy_label]
  end

  defmodule PaginationPolicy do
    @moduledoc """
    Canonical pagination-policy entry referenced by operations.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            strategy: atom(),
            request_mapping: map(),
            response_mapping: map(),
            default_limit: non_neg_integer() | nil,
            items_path: [term()] | nil
          }

    @enforce_keys [
      :id,
      :strategy,
      :request_mapping,
      :response_mapping,
      :default_limit,
      :items_path
    ]
    defstruct [
      :id,
      :strategy,
      :request_mapping,
      :response_mapping,
      :default_limit,
      :items_path
    ]
  end

  defmodule Schema do
    @moduledoc """
    Canonical schema inventory entry for generated provider types.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            module: module(),
            type_name: atom(),
            kind: atom(),
            fields: [map()],
            source_refs: [map()]
          }

    @enforce_keys [:id, :module, :type_name, :kind, :fields, :source_refs]
    defstruct [:id, :module, :type_name, :kind, :fields, :source_refs]
  end

  defmodule DocsInventory do
    @moduledoc """
    Generated docs, guide, and example inventory for one provider snapshot.
    """

    @type t :: %__MODULE__{
            guides: [map()],
            examples: [map()],
            operations: map()
          }

    @enforce_keys [:guides, :examples, :operations]
    defstruct [:guides, :examples, :operations]
  end

  defmodule Artifact do
    @moduledoc """
    One committed generated file declared by the provider artifact plan.
    """

    @type t :: %__MODULE__{
            id: atom(),
            path: String.t(),
            kind: :code | :artifact
          }

    @enforce_keys [:id, :path, :kind]
    defstruct [:id, :path, :kind]
  end

  defmodule ArtifactPlan do
    @moduledoc """
    Final generated file contract and forbidden legacy outputs for a provider.
    """

    @type t :: %__MODULE__{
            generated_code_dir: String.t(),
            artifacts: [Artifact.t()],
            forbidden_paths: [String.t()]
          }

    @enforce_keys [:generated_code_dir, :artifacts, :forbidden_paths]
    defstruct [:generated_code_dir, :artifacts, :forbidden_paths]
  end

  defmodule Fingerprints do
    @moduledoc """
    Source and generation fingerprints for one provider snapshot.
    """

    @type t :: %__MODULE__{
            sources: [map()],
            generation: map()
          }

    @enforce_keys [:sources, :generation]
    defstruct [:sources, :generation]
  end

  @type t :: %__MODULE__{
          provider: Provider.t(),
          runtime_defaults: RuntimeDefaults.t(),
          operations: [Operation.t()],
          schemas: [Schema.t()],
          auth_policies: [AuthPolicy.t()],
          pagination_policies: [PaginationPolicy.t()],
          docs_inventory: DocsInventory.t(),
          artifact_plan: ArtifactPlan.t(),
          fingerprints: Fingerprints.t()
        }

  @enforce_keys [
    :provider,
    :runtime_defaults,
    :operations,
    :schemas,
    :auth_policies,
    :pagination_policies,
    :docs_inventory,
    :artifact_plan,
    :fingerprints
  ]
  defstruct [
    :provider,
    :runtime_defaults,
    :operations,
    :schemas,
    :auth_policies,
    :pagination_policies,
    :docs_inventory,
    :artifact_plan,
    :fingerprints
  ]

  @spec to_map(term()) :: term()
  def to_map(term) do
    normalize_term(term)
  end

  defp normalize_term(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), normalize_term(value)} end)
    |> Map.new()
  end

  defp normalize_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {normalize_key(key), normalize_term(value)} end)
    |> Map.new()
  end

  defp normalize_term(list) when is_list(list), do: Enum.map(list, &normalize_term/1)

  defp normalize_term(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_term/1)
  end

  defp normalize_term(atom) when atom in [nil, true, false], do: atom

  defp normalize_term(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp normalize_term(other), do: other

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)
end
