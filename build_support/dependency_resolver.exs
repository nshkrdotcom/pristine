defmodule Pristine.Build.DependencyResolver do
  @moduledoc false

  @workspace_root Path.expand("..", __DIR__)
  @repo "nshkrdotcom/pristine"

  def pristine_runtime(opts \\ []) do
    resolve(
      :pristine,
      ["apps/pristine_runtime"],
      [github: @repo, branch: "master", subdir: "apps/pristine_runtime"],
      opts
    )
  end

  def pristine_codegen(opts \\ []) do
    resolve(
      :pristine_codegen,
      ["apps/pristine_codegen"],
      [github: @repo, branch: "master", subdir: "apps/pristine_codegen"],
      opts
    )
  end

  def pristine_provider_testkit(opts \\ []) do
    resolve(
      :pristine_provider_testkit,
      ["apps/pristine_provider_testkit"],
      [github: @repo, branch: "master", subdir: "apps/pristine_provider_testkit"],
      opts
    )
  end

  defp resolve(app, local_paths, fallback_opts, opts) do
    case workspace_path(local_paths) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp workspace_path(local_paths) do
    if prefer_workspace_paths?() do
      Enum.find_value(local_paths, &existing_path/1)
    end
  end

  defp prefer_workspace_paths? do
    not Enum.member?(Path.split(@workspace_root), "deps")
  end

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @workspace_root)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
