defmodule Mix.Tasks.Monorepo.Test do
  use Mix.Task
  alias Mix.Tasks.Monorepo.Shared

  @moduledoc false

  @shortdoc "Runs test across the workspace"

  @impl true
  def run(args) do
    previous_env = Mix.env()
    previous_mix_env = System.get_env("MIX_ENV")

    try do
      System.put_env("MIX_ENV", "test")
      Mix.env(:test)
      Shared.run("test", args)
    after
      restore_mix_env(previous_mix_env)
      Mix.env(previous_env)
    end
  end

  defp restore_mix_env(nil), do: System.delete_env("MIX_ENV")
  defp restore_mix_env(value), do: System.put_env("MIX_ENV", value)
end
