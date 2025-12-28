defmodule Mix.Tasks.Pristine.Docs do
  @moduledoc """
  Generates documentation from a Pristine manifest.

  ## Usage

      mix pristine.docs --manifest path/to/manifest.json
      mix pristine.docs --manifest path/to/manifest.json --output docs/api.md
      mix pristine.docs --manifest path/to/manifest.json --format html --output docs/api.html

  ## Options

    * `--manifest` - Path to the Pristine manifest file (required)
    * `--output` - Output file path (default: stdout)
    * `--format` - Output format: markdown or html (default: markdown)
    * `--examples` - Include example requests (default: false)

  ## Examples

      # Output to stdout
      mix pristine.docs --manifest api_manifest.json

      # Write to file
      mix pristine.docs --manifest api_manifest.json --output docs/api.md

      # Generate HTML format
      mix pristine.docs --manifest api_manifest.json --format html --output docs/api.html

      # Include example code snippets
      mix pristine.docs --manifest api_manifest.json --examples

  """

  use Mix.Task

  @shortdoc "Generate documentation from manifest"

  @switches [
    manifest: :string,
    output: :string,
    format: :string,
    examples: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    manifest_path = Keyword.get(opts, :manifest)
    output_path = Keyword.get(opts, :output)
    format = parse_format(Keyword.get(opts, :format))
    doc_opts = [examples: Keyword.get(opts, :examples, false)]

    cond do
      is_nil(manifest_path) ->
        Mix.raise("--manifest option is required")

      not File.exists?(manifest_path) ->
        Mix.raise("Manifest file not found: #{manifest_path}")

      true ->
        generate_docs(manifest_path, output_path, format, doc_opts)
    end
  end

  defp generate_docs(manifest_path, output_path, format, doc_opts) do
    case Pristine.Manifest.load_file(manifest_path) do
      {:ok, manifest} ->
        do_generate(manifest, output_path, format, doc_opts)

      {:error, reason} ->
        Mix.raise("Failed to load manifest: #{inspect(reason)}")
    end
  end

  defp do_generate(manifest, output_path, format, doc_opts) do
    {:ok, docs} =
      case format do
        :markdown -> Pristine.Docs.generate(manifest, doc_opts)
        :html -> Pristine.Docs.generate_html(manifest, doc_opts)
      end

    output_docs(docs, output_path)
  end

  defp parse_format(nil), do: :markdown
  defp parse_format("markdown"), do: :markdown
  defp parse_format("md"), do: :markdown
  defp parse_format("html"), do: :html
  defp parse_format(other), do: Mix.raise("Unknown format: #{other}. Use 'markdown' or 'html'")

  defp output_docs(docs, nil), do: Mix.shell().info(docs)

  defp output_docs(docs, path) do
    File.write!(path, docs)
    Mix.shell().info("Documentation written to #{path}")
  end
end
