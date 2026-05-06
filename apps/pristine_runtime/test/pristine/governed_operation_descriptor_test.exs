defmodule Pristine.GovernedOperationDescriptorTest do
  use ExUnit.Case, async: true

  alias Pristine.GovernedOperationDescriptor

  test "describes governed OpenAPI operations for every adaptive proof use" do
    descriptor = GovernedOperationDescriptor.new!(descriptor_attrs())

    assert descriptor.fixture_ref == "AOC-046"
    assert descriptor.operation_ref == "pristine-operation://github/issues/list"
    assert descriptor.connector_admission_ref == "connector-admission://tenant-1/github"

    assert descriptor.usage_contexts == [
             :tool_task,
             :eval_dataset_loader,
             :generated_sdk,
             :appkit_management_api
           ]

    assert descriptor.raw_material_present? == false
    refute Map.has_key?(descriptor, :api_key)
  end

  test "rejects unmanaged standalone auth material in governed descriptors" do
    for {key, value} <- [
          api_key: "raw-key",
          bearer: "raw-bearer",
          token_file: "/not/used/token.json",
          default_auth: [:raw],
          provider_payload: %{"Authorization" => "Bearer raw"}
        ] do
      error =
        assert_raise ArgumentError, fn ->
          descriptor_attrs()
          |> Keyword.put(key, value)
          |> GovernedOperationDescriptor.new!()
        end

      assert String.contains?(error.message, "governed OpenAPI descriptor rejects unmanaged")
      assert String.contains?(error.message, Atom.to_string(key))
    end
  end

  test "fails closed when an adaptive proof use context is missing" do
    error =
      assert_raise ArgumentError, fn ->
        descriptor_attrs()
        |> Keyword.put(:usage_contexts, [:tool_task, :generated_sdk])
        |> GovernedOperationDescriptor.new!()
      end

    assert String.contains?(error.message, "governed OpenAPI descriptor requires usage_contexts")
  end

  defp descriptor_attrs do
    [
      operation_ref: "pristine-operation://github/issues/list",
      connector_admission_ref: "connector-admission://tenant-1/github",
      provider_account_ref: "provider-account://tenant-1/github/app",
      credential_lease_ref: "credential-lease://tenant-1/github/app",
      operation_policy_ref: "operation-policy://tenant-1/github/issues/list",
      tenant_ref: "tenant://tenant-1",
      subject_ref: "subject://tenant-1/operator/ada",
      trace_ref: "trace://tenant-1/github/issues/list",
      redaction_ref: "redaction://tenant-1/github",
      usage_contexts: [:tool_task, :eval_dataset_loader, :generated_sdk, :appkit_management_api]
    ]
  end
end
