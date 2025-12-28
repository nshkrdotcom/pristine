defmodule Pristine.Ports.Multipart do
  @moduledoc """
  Multipart encoding boundary.
  """

  @callback encode(term(), keyword()) :: {binary(), iodata() | Enumerable.t()}
end
