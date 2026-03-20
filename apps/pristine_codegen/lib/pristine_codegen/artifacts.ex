defmodule PristineCodegen.Artifacts do
  @moduledoc false

  alias PristineCodegen.Compilation
  alias PristineCodegen.JSON
  alias PristineCodegen.ProviderIR
  alias PristineCodegen.RenderedFile

  @spec render(ProviderIR.t(), [RenderedFile.t()]) :: [RenderedFile.t()]
  def render(%ProviderIR{} = provider_ir, rendered_files) when is_list(rendered_files) do
    Enum.flat_map(provider_ir.artifact_plan.artifacts, fn artifact ->
      case artifact.kind do
        :code ->
          []

        :artifact ->
          [
            %RenderedFile{
              kind: :artifact,
              relative_path: artifact.path,
              contents: render_artifact(artifact.id, provider_ir, rendered_files)
            }
          ]
      end
    end)
  end

  @spec write_files(Compilation.t()) :: Compilation.t()
  def write_files(%Compilation{} = compilation) do
    Enum.each(Compilation.all_files(compilation), fn rendered_file ->
      absolute_path = Path.join(compilation.paths.project_root, rendered_file.relative_path)
      File.mkdir_p!(Path.dirname(absolute_path))
      File.write!(absolute_path, rendered_file.contents)
    end)

    compilation
  end

  defp render_artifact(:provider_ir, provider_ir, _rendered_files) do
    JSON.encode!(ProviderIR.to_map(provider_ir))
  end

  defp render_artifact(:generation_manifest, provider_ir, rendered_files) do
    artifact_files =
      provider_ir.artifact_plan.artifacts
      |> Enum.reject(&(&1.kind == :code))
      |> Enum.map(& &1.path)

    manifest = %{
      provider: ProviderIR.to_map(provider_ir.provider),
      generated_files: Enum.map(rendered_files, & &1.relative_path),
      artifact_files: artifact_files,
      operation_count: length(provider_ir.operations),
      schema_count: length(provider_ir.schemas),
      auth_policy_count: length(provider_ir.auth_policies),
      pagination_policy_count: length(provider_ir.pagination_policies),
      fingerprints: ProviderIR.to_map(provider_ir.fingerprints)
    }

    JSON.encode!(manifest)
  end

  defp render_artifact(:docs_inventory, provider_ir, _rendered_files) do
    JSON.encode!(ProviderIR.to_map(provider_ir.docs_inventory))
  end

  defp render_artifact(:source_inventory, provider_ir, _rendered_files) do
    JSON.encode!(%{sources: ProviderIR.to_map(provider_ir.fingerprints.sources)})
  end

  defp render_artifact(:operation_auth_policies, provider_ir, _rendered_files) do
    operation_auth_policies =
      provider_ir.operations
      |> Enum.map(fn operation -> {operation.id, operation.auth_policy_id} end)
      |> Map.new()

    JSON.encode!(operation_auth_policies)
  end
end
