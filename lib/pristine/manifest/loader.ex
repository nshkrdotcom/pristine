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
        {:error, :yaml_not_supported}

      ".yml" ->
        {:error, :yaml_not_supported}

      other ->
        {:error, {:unsupported_extension, other}}
    end
  end
end
