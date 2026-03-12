defmodule Pristine.Runtime do
  @moduledoc """
  Runtime entrypoint for manifest-driven execution.
  """

  alias Pristine.Core.{Context, Pipeline, Types}
  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint

  @spec build_context!(Manifest.t() | map(), keyword()) :: Context.t()
  def build_context!(manifest_input, opts \\ []) do
    case ensure_manifest(manifest_input) do
      {:ok, manifest} ->
        prepare_context(manifest, Context.new(opts))

      {:error, reason} ->
        raise ArgumentError, "invalid manifest: #{inspect(reason)}"
    end
  end

  @spec execute(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(manifest_input, endpoint_id, payload, %Context{} = context, opts \\ []) do
    with {:ok, manifest} <- ensure_manifest(manifest_input),
         context <- prepare_context(manifest, context) do
      Pipeline.execute(manifest, endpoint_id, payload, context, opts)
    end
  end

  @spec execute_endpoint(Endpoint.t(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_endpoint(%Endpoint{} = endpoint, payload, %Context{} = context, opts \\ []) do
    security = Keyword.get(opts, :security)
    execute_opts = Keyword.delete(opts, :security)
    Pipeline.execute_endpoint(endpoint, security, payload, context, execute_opts)
  end

  @spec execute_stream(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_stream(manifest_input, endpoint_id, payload, %Context{} = context, opts \\ []) do
    with {:ok, manifest} <- ensure_manifest(manifest_input),
         context <- prepare_context(manifest, context) do
      Pipeline.execute_stream(manifest, endpoint_id, payload, context, opts)
    end
  end

  @spec execute_future(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, Task.t()} | {:error, term()}
  def execute_future(manifest_input, endpoint_id, payload, %Context{} = context, opts \\ []) do
    with {:ok, manifest} <- ensure_manifest(manifest_input),
         context <- prepare_context(manifest, context) do
      Pipeline.execute_future(manifest, endpoint_id, payload, context, opts)
    end
  end

  @spec prepare_context(Manifest.t(), Context.t()) :: Context.t()
  def prepare_context(%Manifest{} = manifest, %Context{} = context) do
    context
    |> maybe_put_base_url(manifest.base_url)
    |> merge_retry_policies(manifest.retry_policies)
    |> merge_type_schemas(manifest.types)
  end

  defp ensure_manifest(%Manifest{} = manifest), do: {:ok, manifest}
  defp ensure_manifest(input) when is_map(input), do: Manifest.load(input)
  defp ensure_manifest(_), do: {:error, :invalid_manifest}

  defp maybe_put_base_url(%Context{base_url: base_url} = context, _manifest_base_url)
       when is_binary(base_url) and base_url != "" do
    context
  end

  defp maybe_put_base_url(%Context{} = context, manifest_base_url)
       when is_binary(manifest_base_url) do
    %{context | base_url: manifest_base_url}
  end

  defp maybe_put_base_url(%Context{} = context, _manifest_base_url), do: context

  defp merge_retry_policies(%Context{} = context, policies) when is_map(policies) do
    merged = Map.merge(policies, context.retry_policies || %{})
    %{context | retry_policies: merged}
  end

  defp merge_retry_policies(%Context{} = context, _policies), do: context

  defp merge_type_schemas(%Context{} = context, manifest_types) when is_map(manifest_types) do
    if manifest_type_keys_loaded?(context.type_schemas, manifest_types) do
      context
    else
      compiled = Types.compile(manifest_types)
      %{context | type_schemas: Map.merge(compiled, context.type_schemas || %{})}
    end
  end

  defp merge_type_schemas(%Context{} = context, _manifest_types), do: context

  defp manifest_type_keys_loaded?(existing, manifest_types)
       when is_map(existing) and is_map(manifest_types) do
    manifest_types
    |> Map.keys()
    |> Enum.all?(&Map.has_key?(existing, &1))
  end

  defp manifest_type_keys_loaded?(_existing, _manifest_types), do: false
end
