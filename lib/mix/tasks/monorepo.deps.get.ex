defmodule Mix.Tasks.Monorepo.Deps.Get do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs deps.get across the workspace"

  @impl true
  def run(args) do
    Shared.run("deps.get", args)
  end
end
