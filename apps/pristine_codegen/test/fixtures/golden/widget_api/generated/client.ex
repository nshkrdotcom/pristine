defmodule WidgetAPI.Generated.Client do
  @moduledoc """
  Generated Widget API client facade over `WidgetAPI.Client`.
  """

  @spec new(keyword()) :: WidgetAPI.Client.t()
  def new(opts \\ []) when is_list(opts) do
    WidgetAPI.Client.new(opts)
  end
end
