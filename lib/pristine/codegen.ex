defmodule Pristine.Codegen do
  @moduledoc """
  Generate Elixir modules from manifests.
  """

  alias Pristine.Codegen.Elixir, as: ElixirCodegen
  alias Pristine.Manifest

  @spec build_sources(Manifest.t() | map(), keyword()) ::
          {:ok, map()} | {:error, :invalid_manifest | [String.t()]}
  def build_sources(manifest_input, opts \\ []) do
    with {:ok, manifest} <- normalize_manifest(manifest_input) do
      namespace = Keyword.get(opts, :namespace, "Pristine.Generated")
      output_dir = Keyword.get(opts, :output_dir, "lib/generated")

      type_sources =
        manifest.types
        |> Enum.map(fn {name, defn} ->
          module_source = ElixirCodegen.render_type_module("#{namespace}.Types", name, defn)
          path = Path.join([output_dir, "types", "#{Macro.underscore(name)}.ex"])
          {path, module_source}
        end)
        |> Map.new()

      client_source =
        ElixirCodegen.render_client_module("#{namespace}.Client", manifest_to_map(manifest))

      client_path = Path.join(output_dir, "client.ex")

      {:ok, Map.put(type_sources, client_path, client_source)}
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

  defp manifest_to_map(%Manifest{} = manifest) do
    %{
      name: manifest.name,
      version: manifest.version,
      endpoints:
        Enum.map(manifest.endpoints, fn {_id, endpoint} -> Map.from_struct(endpoint) end),
      types: manifest.types,
      policies: manifest.policies
    }
  end
end
