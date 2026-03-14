defmodule Pristine.Adapters.OAuthBrowser.SystemCmd do
  @moduledoc """
  System-command browser launcher adapter for interactive OAuth flows.
  """

  @behaviour Pristine.Ports.OAuthBrowser

  @impl true
  defdelegate open(url, opts \\ []), to: Pristine.OAuth2.Browser
end
