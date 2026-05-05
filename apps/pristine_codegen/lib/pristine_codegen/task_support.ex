defmodule PristineCodegen.TaskSupport do
  @moduledoc false

  @spec parse!(list(String.t())) :: {module(), keyword()}
  def parse!(args) when is_list(args) do
    {opts, positional, []} = OptionParser.parse(args, strict: [project_root: :string])

    provider_module =
      case positional do
        [provider_module] ->
          provider_module
          |> String.split(".")
          |> Module.safe_concat()

        _other ->
          Mix.raise("expected a provider module argument")
      end

    {provider_module, opts}
  end

  @spec provider_label(module()) :: String.t()
  def provider_label(provider_module) when is_atom(provider_module) do
    provider_module
    |> Module.split()
    |> List.last()
  end
end
