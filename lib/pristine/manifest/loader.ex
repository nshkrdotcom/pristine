defmodule Pristine.Manifest.Loader do
  @moduledoc """
  Load manifest files from disk.
  """

  @spec load_file(Path.t()) :: {:ok, map()} | {:error, term()}
  def load_file(path) do
    case Path.extname(path) do
      ".json" ->
        with {:ok, data} <- File.read(path) do
          Jason.decode(data)
        end

      ".exs" ->
        {manifest, _binding} = Code.eval_file(path)
        {:ok, manifest}

      ".yaml" ->
        decode_yaml_or_json(path)

      ".yml" ->
        decode_yaml_or_json(path)

      other ->
        {:error, {:unsupported_extension, other}}
    end
  end

  defp decode_yaml_or_json(path) do
    with {:ok, data} <- File.read(path),
         {:ok, manifest} <- Jason.decode(data) do
      {:ok, manifest}
    else
      {:error, _} -> {:error, :yaml_not_supported}
    end
  end
end
