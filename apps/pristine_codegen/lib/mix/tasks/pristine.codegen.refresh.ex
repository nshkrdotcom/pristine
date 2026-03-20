defmodule Mix.Tasks.Pristine.Codegen.Refresh do
  use Mix.Task

  @moduledoc false
  @shortdoc "Refresh upstream provider inputs and regenerate committed artifacts"

  @impl Mix.Task
  def run(args) do
    {provider_module, opts} = PristineCodegen.TaskSupport.parse!(args)
    Mix.Task.run("compile")

    {:ok, compilation} = PristineCodegen.refresh(provider_module, opts)

    provider_name =
      compilation.provider_ir.provider.base_module |> inspect() |> String.trim_leading("Elixir.")

    Mix.shell().info("refreshed #{provider_name}")
  end
end
