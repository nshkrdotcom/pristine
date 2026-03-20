defmodule PristineProviderTestkit.Conformance do
  @moduledoc """
  Shared provider conformance helper built on top of the `pristine_codegen`
  compiler and final artifact freshness contract.
  """

  @spec verify_provider(module(), keyword()) :: :ok | {:error, map()}
  def verify_provider(provider_module, opts \\ [])
      when is_atom(provider_module) and is_list(opts) do
    case Keyword.get(opts, :write?, false) do
      true ->
        opts = Keyword.delete(opts, :write?)
        {:ok, _compilation} = PristineCodegen.generate(provider_module, opts)
        :ok

      false ->
        PristineCodegen.verify(provider_module, opts)
    end
  end
end
