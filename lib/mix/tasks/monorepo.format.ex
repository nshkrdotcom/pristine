defmodule Mix.Tasks.Monorepo.Format do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs format across the workspace"

  @impl true
  def run(args) do
    Shared.run("format", args)
  end
end
