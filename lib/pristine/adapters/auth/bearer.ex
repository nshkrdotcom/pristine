defmodule Pristine.Adapters.Auth.Bearer do
  @moduledoc """
  Bearer token auth adapter.
  """

  @behaviour Pristine.Ports.Auth

  @impl true
  def headers(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} -> {:ok, %{"Authorization" => "Bearer #{token}"}}
      :error -> {:error, :missing_bearer_token}
    end
  end
end
