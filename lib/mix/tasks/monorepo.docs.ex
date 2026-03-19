defmodule Mix.Tasks.Monorepo.Docs do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs docs across the workspace"

  @impl true
  def run(args) do
    Shared.run("docs", args)
  end
end
