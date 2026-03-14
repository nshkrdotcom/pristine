defmodule Pristine.Core.Response do
  @moduledoc """
  Internal normalized response data from the transport port.

  Provider SDKs should prefer `Pristine.SDK.Response` when they need a public
  response helper.
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
