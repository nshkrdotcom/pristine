defmodule Pristine.Ports.Auth do
  @moduledoc """
  Auth boundary for producing headers.
  """

  @callback headers(keyword()) :: {:ok, map()} | {:error, term()}
end
