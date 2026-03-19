defmodule Mix.Tasks.Monorepo.Shared do
  @moduledoc false

  def run(task, args) when is_binary(task) and is_list(args) do
    root = workspace_root()

    project_paths()
    |> Enum.each(fn project_path ->
      run_task(project_path, root, task, args)
    end)
  end

  defp workspace_root do
    Mix.Project.config()
    |> Keyword.fetch!(:blitz_workspace)
    |> Keyword.fetch!(:root)
    |> Path.expand()
  end

  defp project_paths do
    workspace = Mix.Project.config()[:blitz_workspace] || []
    root = workspace_root()

    workspace
    |> Keyword.fetch!(:projects)
    |> Enum.flat_map(fn
      "." -> [root]
      pattern -> Path.wildcard(Path.join(root, pattern))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp run_task(project_path, root, task, args) do
    Mix.shell().info(
      "==> #{project_label(project_path, root)}: mix #{task} #{Enum.join(args, " ")}"
    )

    {command, command_args} = mix_command(task, args)

    case System.cmd(command, command_args, cd: project_path, into: IO.binstream(:stdio, :line)) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise(
          "workspace task failed in #{project_label(project_path, root)} with status #{status}"
        )
    end
  end

  defp project_label(project_path, root) do
    case Path.relative_to(project_path, root) do
      "." -> "."
      label -> label
    end
  end

  defp mix_command(task, args) do
    case System.get_env("PRISTINE_MONOREPO_MIX_PATCH_PATH") do
      nil ->
        {"mix", [task | args]}

      patch_path ->
        {"elixir", ["-pa", patch_path, "-e", "Mix.CLI.main()", "--", task | args]}
    end
  end
end
