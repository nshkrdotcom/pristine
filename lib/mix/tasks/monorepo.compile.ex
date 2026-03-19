defmodule Mix.Tasks.Monorepo.Compile do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs compile --warnings-as-errors across the workspace"

  @impl true
  def run(args) do
    args = ensure_flag(args, "--warnings-as-errors")
    Shared.run("compile", args)
  end

  defp ensure_flag(args, flag) do
    if flag in args, do: args, else: [flag | args]
  end
end
