defmodule PristineCodegen.Plugin.Docs do
  @moduledoc """
  Docs/example plugin contract for `ProviderIR` enrichment.
  """

  alias PristineCodegen.ProviderIR

  @callback transform(ProviderIR.t(), keyword()) :: ProviderIR.t()
end
