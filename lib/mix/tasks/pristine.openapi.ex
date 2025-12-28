defmodule Mix.Tasks.Pristine.Openapi do
  @moduledoc """
  Generates OpenAPI specification from a Pristine manifest.

  ## Usage

      mix pristine.openapi --manifest path/to/manifest.json
      mix pristine.openapi --manifest path/to/manifest.json --output openapi.json
      mix pristine.openapi --manifest path/to/manifest.json --output openapi.yaml --format yaml

  ## Options

    * `--manifest` - Path to the Pristine manifest file (required)
    * `--output` - Output file path (default: stdout)
    * `--format` - Output format: json or yaml (default: json)

  ## Examples

      # Output to stdout
      mix pristine.openapi --manifest api_manifest.json

      # Write to file
      mix pristine.openapi --manifest api_manifest.json --output openapi.json

      # Generate YAML format
      mix pristine.openapi --manifest api_manifest.json --output openapi.yaml --format yaml

  """

  use Mix.Task

  @shortdoc "Generate OpenAPI spec from manifest"

  @switches [
    manifest: :string,
    output: :string,
    format: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    manifest_path = Keyword.get(opts, :manifest)
    output_path = Keyword.get(opts, :output)
    format = parse_format(Keyword.get(opts, :format))

    cond do
      is_nil(manifest_path) ->
        Mix.raise("--manifest option is required")

      not File.exists?(manifest_path) ->
        Mix.raise("Manifest file not found: #{manifest_path}")

      true ->
        generate_spec(manifest_path, output_path, format)
    end
  end

  defp generate_spec(manifest_path, output_path, format) do
    case Pristine.Manifest.load_file(manifest_path) do
      {:ok, manifest} ->
        do_generate(manifest, output_path, format)

      {:error, reason} ->
        Mix.raise("Failed to load manifest: #{inspect(reason)}")
    end
  end

  defp do_generate(manifest, output_path, format) do
    {:ok, spec} = Pristine.OpenAPI.generate(manifest, format: format)
    output_spec(spec, output_path)
  end

  defp parse_format(nil), do: :json
  defp parse_format("json"), do: :json
  defp parse_format("yaml"), do: :yaml
  defp parse_format("yml"), do: :yaml
  defp parse_format(other), do: Mix.raise("Unknown format: #{other}. Use 'json' or 'yaml'")

  defp output_spec(spec, nil), do: Mix.shell().info(spec)

  defp output_spec(spec, path) do
    File.write!(path, spec)
    Mix.shell().info("OpenAPI spec written to #{path}")
  end
end
