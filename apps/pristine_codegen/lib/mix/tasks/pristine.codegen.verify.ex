defmodule Mix.Tasks.Pristine.Codegen.Verify do
  use Mix.Task

  @moduledoc false
  @shortdoc "Verify provider generated artifacts are current"

  @impl Mix.Task
  def run(args) do
    {provider_module, opts} = PristineCodegen.TaskSupport.parse!(args)
    Mix.Task.run("compile")

    provider_name =
      provider_module
      |> PristineCodegen.Provider.definition(opts)
      |> Map.fetch!(:provider)
      |> Map.fetch!(:base_module)
      |> inspect()
      |> String.trim_leading("Elixir.")

    case PristineCodegen.verify(provider_module, opts) do
      :ok ->
        Mix.shell().info("verified #{provider_name}")

      {:error, failures} ->
        Mix.raise("""
        generated artifacts are stale
        missing: #{Enum.join(failures.missing_paths, ", ")}
        stale: #{Enum.join(failures.stale_paths, ", ")}
        forbidden: #{Enum.join(failures.forbidden_paths, ", ")}
        """)
    end
  end
end
