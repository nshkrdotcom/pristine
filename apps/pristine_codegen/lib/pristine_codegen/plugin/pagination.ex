defmodule PristineCodegen.Plugin.Pagination do
  @moduledoc """
  Pagination plugin contract for canonical pagination-policy enrichment.
  """

  alias PristineCodegen.ProviderIR

  @callback transform(ProviderIR.t(), keyword()) :: ProviderIR.t()
end
