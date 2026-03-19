defmodule Pristine.Adapters.OAuthCallbackListener.Bandit do
  @moduledoc """
  Bandit-backed loopback callback listener adapter for interactive OAuth flows.
  """

  @behaviour Pristine.Ports.OAuthCallbackListener

  @impl true
  defdelegate start(redirect_uri, opts \\ []), to: Pristine.OAuth2.CallbackServer

  @impl true
  defdelegate await(server, timeout_ms), to: Pristine.OAuth2.CallbackServer

  @impl true
  defdelegate stop(server), to: Pristine.OAuth2.CallbackServer

  @impl true
  defdelegate loopback_redirect_uri?(redirect_uri), to: Pristine.OAuth2.CallbackServer
end
