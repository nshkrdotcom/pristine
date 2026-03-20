defmodule PristineProviderTestkit.Artifacts do
  @moduledoc """
  Small helpers for provider repos that need to assert committed artifacts
  exist before deeper freshness checks run.
  """

  @spec missing_paths([Path.t()]) :: [Path.t()]
  def missing_paths(paths) when is_list(paths) do
    Enum.reject(paths, &File.exists?/1)
  end

  @spec stale_paths([map()], Path.t()) :: [Path.t()]
  def stale_paths(expected_files, project_root)
      when is_list(expected_files) and is_binary(project_root) do
    expected_files
    |> Enum.flat_map(fn %{path: path, contents: expected_contents} ->
      absolute_path = Path.join(project_root, path)

      case File.read(absolute_path) do
        {:ok, contents} when contents == expected_contents -> []
        {:ok, _contents} -> [path]
        {:error, _reason} -> []
      end
    end)
  end
end
