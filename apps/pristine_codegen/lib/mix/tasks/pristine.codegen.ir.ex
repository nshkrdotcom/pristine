defmodule Mix.Tasks.Pristine.Codegen.Ir do
  use Mix.Task

  @moduledoc false
  @shortdoc "Emit canonical ProviderIR JSON for inspection"

  @impl Mix.Task
  def run(args) do
    {provider_module, opts} = PristineCodegen.TaskSupport.parse!(args)
    Mix.Task.run("compile")
    {:ok, provider_ir_json} = PristineCodegen.emit_ir(provider_module, opts)
    Mix.shell().info(provider_ir_json)
  end
end
