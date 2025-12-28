defmodule Pristine.Ports.Transport do
  @moduledoc """
  Transport boundary for sending requests.
  """

  alias Pristine.Core.{Context, Request, Response}

  @callback send(Request.t(), Context.t()) :: {:ok, Response.t()} | {:error, term()}
end
