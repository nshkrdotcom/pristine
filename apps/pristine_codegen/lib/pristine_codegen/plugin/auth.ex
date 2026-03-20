defmodule PristineCodegen.Plugin.Auth do
  @moduledoc """
  Auth plugin contract for canonical auth-policy enrichment.
  """

  alias PristineCodegen.ProviderIR

  @callback transform(ProviderIR.t(), keyword()) :: ProviderIR.t()
end
