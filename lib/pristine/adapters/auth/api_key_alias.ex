defmodule Pristine.Adapters.Auth.APIKey do
  @moduledoc false

  @behaviour Pristine.Ports.Auth

  alias Pristine.Adapters.Auth.ApiKey

  def new(value, opts \\ []) do
    ApiKey.new(value, opts)
  end

  @impl true
  def headers(opts) do
    ApiKey.headers(opts)
  end
end
