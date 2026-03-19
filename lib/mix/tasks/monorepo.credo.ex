defmodule Mix.Tasks.Monorepo.Credo do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs credo across the workspace"

  @impl true
  def run(args) do
    Shared.run("credo", args)
  end
end
