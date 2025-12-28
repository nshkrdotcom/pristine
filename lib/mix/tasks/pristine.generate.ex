defmodule Mix.Tasks.Pristine.Generate do
  @moduledoc """
  Generate Elixir modules from a manifest file.

  Usage:
    mix pristine.generate --manifest path/to/manifest.json --output lib/generated
  """

  use Mix.Task

  alias Pristine.Codegen

  @shortdoc "Generate Pristine modules from a manifest"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: [manifest: :string, output: :string, namespace: :string])

    manifest_path = Keyword.get(opts, :manifest)
    output_dir = Keyword.get(opts, :output, "lib/generated")
    namespace = Keyword.get(opts, :namespace, "Pristine.Generated")

    if is_nil(manifest_path) do
      Mix.raise("--manifest is required")
    end

    with {:ok, manifest} <- Pristine.Manifest.load_file(manifest_path),
         {:ok, sources} <-
           Codegen.build_sources(manifest, output_dir: output_dir, namespace: namespace) do
      Codegen.write_sources(sources)
      Mix.shell().info("Generated #{map_size(sources)} files in #{output_dir}")
    else
      {:error, reason} ->
        Mix.raise("generation failed: #{inspect(reason)}")
    end
  end
end
