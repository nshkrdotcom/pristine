defmodule Pristine.Core.Response do
  @moduledoc """
  Normalized response data from the transport port.
  """

  defstruct status: nil,
            headers: %{},
            body: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          status: integer() | nil,
          headers: map(),
          body: binary() | nil,
          metadata: map()
        }
end
