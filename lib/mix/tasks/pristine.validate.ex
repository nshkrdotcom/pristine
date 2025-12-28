defmodule Mix.Tasks.Pristine.Validate do
  @moduledoc """
  Validates a Pristine manifest file.

  ## Usage

      mix pristine.validate --manifest path/to/manifest.json [--format text|json]

  ## Options

    * `--manifest` - Path to the manifest file (required)
    * `--format` - Output format: "text" (default) or "json"

  ## Examples

      mix pristine.validate --manifest api_manifest.json
      mix pristine.validate --manifest api_manifest.json --format json

  """

  use Mix.Task

  @shortdoc "Validate a Pristine manifest file"

  @switches [
    manifest: :string,
    format: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    manifest_path = Keyword.get(opts, :manifest)
    format = Keyword.get(opts, :format, "text")

    cond do
      is_nil(manifest_path) ->
        output_error("Missing required --manifest argument", format)
        print_usage()
        exit({:shutdown, 1})

      not File.exists?(manifest_path) ->
        output_error("Manifest file not found: #{manifest_path}", format)
        exit({:shutdown, 1})

      true ->
        validate_manifest(manifest_path, format)
    end
  end

  defp validate_manifest(path, format) do
    case Pristine.Manifest.load_file(path) do
      {:ok, manifest} ->
        output_success(manifest, format)

      {:error, errors} ->
        output_errors(errors, format)
        exit({:shutdown, 1})
    end
  end

  defp output_success(manifest, "json") do
    result = %{
      valid: true,
      name: manifest.name,
      version: manifest.version,
      endpoint_count: map_size(manifest.endpoints),
      type_count: map_size(manifest.types)
    }

    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp output_success(manifest, _text) do
    Mix.shell().info("""
    Manifest is valid

      Name: #{manifest.name}
      Version: #{manifest.version}
      Endpoints: #{map_size(manifest.endpoints)}
      Types: #{map_size(manifest.types)}
    """)
  end

  defp output_error(message, "json") do
    result = %{valid: false, errors: [%{message: message}]}
    Mix.shell().error(Jason.encode!(result, pretty: true))
  end

  defp output_error(message, _text) do
    Mix.shell().error("Error: #{message}")
  end

  defp output_errors(errors, "json") do
    formatted = Enum.map(errors, &format_error_json/1)
    result = %{valid: false, errors: formatted}
    Mix.shell().error(Jason.encode!(result, pretty: true))
  end

  defp output_errors(errors, _text) do
    Mix.shell().error("Manifest validation failed:\n")

    Enum.each(errors, fn error ->
      Mix.shell().error("  - #{format_error_text(error)}")
    end)
  end

  defp format_error_json(%{message: msg, path: path}) do
    %{message: msg, path: Enum.join(path, ".")}
  end

  defp format_error_json(%{message: msg}) do
    %{message: msg}
  end

  defp format_error_json(error) when is_binary(error) do
    %{message: error}
  end

  defp format_error_json(error) do
    %{message: inspect(error)}
  end

  defp format_error_text(%{message: msg, path: path}) do
    "#{Enum.join(path, ".")}: #{msg}"
  end

  defp format_error_text(%{message: msg}) do
    msg
  end

  defp format_error_text(error) when is_binary(error) do
    error
  end

  defp format_error_text(error) do
    inspect(error)
  end

  defp print_usage do
    Mix.shell().info("""

    Usage: mix pristine.validate --manifest PATH [--format text|json]

    Options:
      --manifest  Path to the manifest file (required)
      --format    Output format: text (default) or json
    """)
  end
end
