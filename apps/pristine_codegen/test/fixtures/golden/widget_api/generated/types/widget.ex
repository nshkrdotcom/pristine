defmodule WidgetAPI.Generated.Types.Widget do
  @moduledoc """
  Generated Widget API type for widget.
  """

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t()
        }
end
