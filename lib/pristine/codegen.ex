defmodule Pristine.Codegen do
  @moduledoc """
  Generate Elixir modules from manifests.

  This module orchestrates the generation of SDK-quality Elixir code from
  manifest definitions, including:

  - **Client module**: Main entry point with resource accessors and ungrouped endpoints
  - **Resource modules**: Per-resource endpoint groupings (e.g., `Client.models()`)
  - **Type modules**: Structured types with Sinter schemas

  ## Example

      {:ok, manifest} = Pristine.Manifest.load_file("manifest.yaml")
      {:ok, sources} = Pristine.Codegen.build_sources(manifest, namespace: "MyAPI")
      :ok = Pristine.Codegen.write_sources(sources)

  """

  alias Pristine.Codegen.Elixir, as: ElixirCodegen
  alias Pristine.Codegen.{Resource, Type}
  alias Pristine.Manifest

  @spec build_sources(Manifest.t() | map(), keyword()) ::
          {:ok, map()} | {:error, :invalid_manifest | [String.t()]}
  def build_sources(manifest_input, opts \\ []) do
    with {:ok, manifest} <- normalize_manifest(manifest_input) do
      namespace = Keyword.get(opts, :namespace, "Pristine.Generated")
      output_dir = Keyword.get(opts, :output_dir, "lib/generated")

      sources = %{}

      # Generate type modules
      sources = Map.merge(sources, build_type_sources(manifest, namespace, output_dir))

      # Generate resource modules
      sources = Map.merge(sources, build_resource_sources(manifest, namespace, output_dir))

      # Generate client module
      sources = Map.merge(sources, build_client_sources(manifest, namespace, output_dir))

      {:ok, sources}
    end
  end

  @spec write_sources(map()) :: :ok
  def write_sources(sources) when is_map(sources) do
    Enum.each(sources, fn {path, source} ->
      path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(path, source)
    end)

    :ok
  end

  defp normalize_manifest(%Manifest{} = manifest), do: {:ok, manifest}
  defp normalize_manifest(input) when is_map(input), do: Manifest.load(input)
  defp normalize_manifest(_), do: {:error, :invalid_manifest}

  defp build_type_sources(manifest, namespace, output_dir) do
    type_namespace = "#{namespace}.Types"

    type_namespace
    |> Type.render_all_type_modules(manifest.types)
    |> Enum.map(fn {module_name, source} ->
      # Extract type name from module name
      type_name = String.replace_prefix(module_name, "#{type_namespace}.", "")
      path = Path.join([output_dir, "types", "#{Macro.underscore(type_name)}.ex"])
      {path, source}
    end)
    |> Map.new()
  end

  defp build_resource_sources(manifest, namespace, output_dir) do
    endpoints = endpoints_list(manifest)

    namespace
    |> Resource.render_all_resource_modules(endpoints, manifest.types)
    |> Enum.map(fn {module_name, source} ->
      # Extract resource name from module name
      resource_name = String.replace_prefix(module_name, "#{namespace}.", "")
      path = Path.join([output_dir, "resources", "#{Macro.underscore(resource_name)}.ex"])
      {path, source}
    end)
    |> Map.new()
  end

  defp build_client_sources(manifest, namespace, output_dir) do
    client_module = "#{namespace}.Client"
    client_source = ElixirCodegen.render_client_module(client_module, manifest_to_map(manifest))
    client_path = Path.join(output_dir, "client.ex")

    %{client_path => client_source}
  end

  defp manifest_to_map(%Manifest{} = manifest) do
    %{
      name: manifest.name,
      version: manifest.version,
      endpoints: endpoints_list(manifest) |> Enum.map(&Map.from_struct/1),
      types: manifest.types,
      policies: manifest.policies
    }
  end

  defp endpoints_list(%Manifest{endpoints: endpoints}) when is_map(endpoints) do
    Enum.map(endpoints, fn {_id, endpoint} -> endpoint end)
  end

  defp endpoints_list(%Manifest{endpoints: endpoints}) when is_list(endpoints) do
    endpoints
  end

  defp endpoints_list(_), do: []
end
