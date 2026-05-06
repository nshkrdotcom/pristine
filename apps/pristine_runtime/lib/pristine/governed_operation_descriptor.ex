defmodule Pristine.GovernedOperationDescriptor do
  @moduledoc """
  Standalone-safe descriptor for governed OpenAPI operation admission.

  This does not call Jido or Citadel. It gives generated SDKs and callers a
  ref-only value that can be handed to the owning control plane for admission.
  """

  @required_fields [
    :operation_ref,
    :connector_admission_ref,
    :provider_account_ref,
    :credential_lease_ref,
    :operation_policy_ref,
    :tenant_ref,
    :subject_ref,
    :trace_ref,
    :redaction_ref
  ]
  @usage_contexts [
    :tool_task,
    :eval_dataset_loader,
    :generated_sdk,
    :appkit_management_api
  ]
  @unmanaged_fields [
    :api_key,
    :auth,
    :bearer,
    :default_auth,
    :default_client,
    :oauth_token_source,
    :provider_payload,
    :request_auth,
    :token_file
  ]
  @known_string_keys %{
    "api_key" => :api_key,
    "auth" => :auth,
    "bearer" => :bearer,
    "connector_admission_ref" => :connector_admission_ref,
    "credential_lease_ref" => :credential_lease_ref,
    "default_auth" => :default_auth,
    "default_client" => :default_client,
    "oauth_token_source" => :oauth_token_source,
    "operation_policy_ref" => :operation_policy_ref,
    "operation_ref" => :operation_ref,
    "provider_account_ref" => :provider_account_ref,
    "provider_payload" => :provider_payload,
    "redaction_ref" => :redaction_ref,
    "request_auth" => :request_auth,
    "subject_ref" => :subject_ref,
    "tenant_ref" => :tenant_ref,
    "token_file" => :token_file,
    "trace_ref" => :trace_ref,
    "usage_contexts" => :usage_contexts
  }

  @enforce_keys @required_fields ++ [:fixture_ref, :usage_contexts, :raw_material_present?]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = descriptor), do: descriptor

  def new!(opts) when is_map(opts) or is_list(opts) do
    opts = normalize(opts)

    reject_unmanaged!(opts)
    require_fields!(opts)
    usage_contexts = require_usage_contexts!(Map.get(opts, :usage_contexts, []))

    struct!(__MODULE__,
      fixture_ref: "AOC-046",
      operation_ref: Map.fetch!(opts, :operation_ref),
      connector_admission_ref: Map.fetch!(opts, :connector_admission_ref),
      provider_account_ref: Map.fetch!(opts, :provider_account_ref),
      credential_lease_ref: Map.fetch!(opts, :credential_lease_ref),
      operation_policy_ref: Map.fetch!(opts, :operation_policy_ref),
      tenant_ref: Map.fetch!(opts, :tenant_ref),
      subject_ref: Map.fetch!(opts, :subject_ref),
      trace_ref: Map.fetch!(opts, :trace_ref),
      redaction_ref: Map.fetch!(opts, :redaction_ref),
      usage_contexts: usage_contexts,
      raw_material_present?: false
    )
  end

  defp normalize(opts) when is_list(opts), do: opts |> Map.new() |> normalize()

  defp normalize(opts) when is_map(opts) do
    Map.new(opts, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: Map.get(@known_string_keys, key, key)

  defp reject_unmanaged!(opts) do
    case Enum.find(@unmanaged_fields, &present?(Map.get(opts, &1))) do
      nil ->
        :ok

      key ->
        raise ArgumentError,
              "governed OpenAPI descriptor rejects unmanaged #{key}; use admission refs"
    end
  end

  defp require_fields!(opts) do
    missing = Enum.reject(@required_fields, &present?(Map.get(opts, &1)))

    if missing != [] do
      raise ArgumentError, "governed OpenAPI descriptor requires #{Enum.join(missing, ", ")}"
    end
  end

  defp require_usage_contexts!(contexts) when is_list(contexts) do
    missing = Enum.reject(@usage_contexts, &(&1 in contexts))

    if missing == [] do
      @usage_contexts
    else
      raise ArgumentError,
            "governed OpenAPI descriptor requires usage_contexts #{Enum.join(missing, ", ")}"
    end
  end

  defp require_usage_contexts!(_contexts) do
    raise ArgumentError, "governed OpenAPI descriptor requires usage_contexts"
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
