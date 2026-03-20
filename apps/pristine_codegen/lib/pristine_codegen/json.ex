defmodule PristineCodegen.JSON do
  @moduledoc false

  @spec encode!(term()) :: String.t()
  def encode!(term) do
    term
    |> Jason.encode_to_iodata!(pretty: true)
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end
end
