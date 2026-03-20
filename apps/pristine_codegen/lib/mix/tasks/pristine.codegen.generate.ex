defmodule Mix.Tasks.Pristine.Codegen.Generate do
  use Mix.Task

  @moduledoc false
  @shortdoc "Generate provider code and committed artifacts from ProviderIR"

  @impl Mix.Task
  def run(args) do
    {provider_module, opts} = PristineCodegen.TaskSupport.parse!(args)
    Mix.Task.run("compile")

    {:ok, compilation} = PristineCodegen.generate(provider_module, opts)

    provider_name =
      compilation.provider_ir.provider.base_module |> inspect() |> String.trim_leading("Elixir.")

    Mix.shell().info("generated #{provider_name}")
  end
end
