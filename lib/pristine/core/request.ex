defmodule Pristine.Core.Request do
  @moduledoc """
  Normalized request data used by the transport port.
  """

  defstruct method: nil,
            url: nil,
            headers: %{},
            body: nil,
            endpoint_id: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          method: String.t() | nil,
          url: String.t() | nil,
          headers: map(),
          body: binary() | nil,
          endpoint_id: String.t() | nil,
          metadata: map()
        }
end
