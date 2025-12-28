defmodule Pristine.Adapters.Auth.ApiKey do
  @moduledoc """
  Static API key auth adapter.
  """

  @behaviour Pristine.Ports.Auth

  @impl true
  def headers(opts) do
    header = Keyword.get(opts, :header, "X-API-Key")

    case Keyword.fetch(opts, :value) do
      {:ok, value} -> {:ok, %{header => value}}
      :error -> {:error, :missing_api_key}
    end
  end
end
