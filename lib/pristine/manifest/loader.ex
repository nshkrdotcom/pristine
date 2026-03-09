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

      ".yaml" ->
        decode_yaml(path)

      ".yml" ->
        decode_yaml(path)

      other ->
        {:error, {:unsupported_extension, other}}
    end
  end

  defp decode_yaml(path), do: YamlElixir.read_from_file(path)
end
