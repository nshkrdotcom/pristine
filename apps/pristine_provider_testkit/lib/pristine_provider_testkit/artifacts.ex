defmodule PristineProviderTestkit.Artifacts do
  @moduledoc """
  Small helpers for provider repos that need to assert committed artifacts
  exist before deeper freshness checks run.
  """

  @spec missing_paths([Path.t()]) :: [Path.t()]
  def missing_paths(paths) when is_list(paths) do
    Enum.reject(paths, &File.exists?/1)
  end
end
