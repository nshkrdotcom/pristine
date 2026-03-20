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
      absolute_path = absolute_path(compilation, rendered_file)
      File.mkdir_p!(Path.dirname(absolute_path))
      File.write!(absolute_path, rendered_file.contents)
    end)

    compilation
  end

  @spec absolute_path(Compilation.t(), RenderedFile.t()) :: String.t()
  def absolute_path(%Compilation{} = compilation, %RenderedFile{} = rendered_file) do
    output_root =
      case rendered_file.kind do
        :code -> compilation.paths.generated_code_dir
        :artifact -> compilation.paths.generated_artifact_dir
      end

    relative_root = relative_root(compilation.provider_ir, rendered_file)

    rendered_file.relative_path
    |> Path.relative_to(relative_root)
    |> then(&Path.join(output_root, &1))
  end

  defp render_artifact(:provider_ir, provider_ir, _rendered_files) do
    JSON.encode!(ProviderIR.to_map(provider_ir))
  end

  defp render_artifact(:generation_manifest, provider_ir, rendered_files) do
    artifact_files =
      provider_ir.artifact_plan.artifacts
      |> Enum.reject(&(&1.kind == :code))
      |> Enum.map(& &1.path)
      |> Enum.sort()

    manifest = %{
      provider: ProviderIR.to_map(provider_ir.provider),
      generated_files: rendered_files |> Enum.map(& &1.relative_path) |> Enum.sort(),
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

  defp relative_root(provider_ir, %RenderedFile{kind: :code}) do
    provider_ir.artifact_plan.generated_code_dir
  end

  defp relative_root(provider_ir, %RenderedFile{kind: :artifact}) do
    provider_ir
    |> artifact_roots()
    |> common_path_prefix()
  end

  defp artifact_roots(provider_ir) do
    provider_ir.artifact_plan.artifacts
    |> Enum.filter(&(&1.kind == :artifact))
    |> Enum.map(&Path.dirname(&1.path))
    |> Enum.uniq()
  end

  defp common_path_prefix([root]), do: root

  defp common_path_prefix([root | roots]) do
    root_segments = Path.split(root)

    roots
    |> Enum.map(&Path.split/1)
    |> Enum.reduce(root_segments, &shared_segments/2)
    |> case do
      [] -> "."
      segments -> Path.join(segments)
    end
  end

  defp common_path_prefix([]), do: "."

  defp shared_segments(path_segments, prefix_segments) do
    path_segments
    |> Enum.zip(prefix_segments)
    |> Enum.take_while(fn {left, right} -> left == right end)
    |> Enum.map(fn {segment, _segment} -> segment end)
  end
end
