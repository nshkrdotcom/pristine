defmodule Pristine.Ports.Streaming do
  @moduledoc """
  Port for SSE decoding and streaming helpers.
  """

  alias Pristine.Streaming.Event

  @type input :: binary() | Enumerable.t()
  @type event :: Event.t()

  @callback decode(input(), keyword()) :: Enumerable.t()
end
