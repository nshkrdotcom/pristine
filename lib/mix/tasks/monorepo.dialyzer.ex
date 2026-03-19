defmodule Mix.Tasks.Monorepo.Dialyzer do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs dialyzer across the workspace"

  @impl true
  def run(args) do
    args = ensure_flag(args, "--force-check")
    Shared.run("dialyzer", args)
  end

  defp ensure_flag(args, flag) do
    if flag in args, do: args, else: [flag | args]
  end
end
