defmodule PristineCodegen.Plugin.Source do
  @moduledoc """
  Source plugin contract for provider-specific upstream extraction.
  """

  alias PristineCodegen.Source.Dataset

  @callback load(module(), keyword()) :: Dataset.t()
end
