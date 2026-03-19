defmodule Pristine.Ports.OAuthBackend.Request do
  @moduledoc """
  Normalized OAuth backend request data prior to transport dispatch.
  """

  defstruct method: nil,
            url: nil,
            headers: %{},
            body: nil,
            id: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          method: atom() | nil,
          url: String.t() | nil,
          headers: map(),
          body: binary() | iodata() | nil,
          id: String.t() | nil,
          metadata: map()
        }
end
