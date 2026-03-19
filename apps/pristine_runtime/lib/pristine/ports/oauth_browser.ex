defmodule Pristine.Ports.OAuthBrowser do
  @moduledoc """
  Boundary for best-effort browser launch in interactive OAuth flows.
  """

  @callback open(String.t(), keyword()) :: :ok | {:error, term()}
end
