defmodule Pristine.Adapters.Multipart.Ex do
  @moduledoc """
  Multipart adapter backed by multipart_ex.
  """

  @behaviour Pristine.Ports.Multipart

  @impl true
  def encode(payload, opts \\ []) do
    Multipart.encode(payload, opts)
  end
end
