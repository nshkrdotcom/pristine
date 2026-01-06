defmodule Pristine.Runtime do
  @moduledoc """
  Runtime entrypoint for manifest-driven execution.
  """

  alias Pristine.Core.{Context, Pipeline, Types}
  alias Pristine.Manifest

  @spec execute(Manifest.t() | map(), String.t() | atom(), term(), Context.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(manifest_input, endpoint_id, payload, %Context{} = context, opts \\ []) do
    with {:ok, manifest} <- ensure_manifest(manifest_input),
         context <- prepare_context(manifest, context) do
      Pipeline.execute(manifest, endpoint_id, payload, context, opts)
    end
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

  defp prepare_context(manifest, %Context{} = context) do
    type_schemas = Types.compile(manifest.types)
    %{context | type_schemas: type_schemas}
  end

  defp ensure_manifest(%Manifest{} = manifest), do: {:ok, manifest}
  defp ensure_manifest(input) when is_map(input), do: Manifest.load(input)
  defp ensure_manifest(_), do: {:error, :invalid_manifest}
end
