defmodule Pristine.Adapters.TokenSource.Static do
  @moduledoc """
  Static token source useful for tests and simple callers.
  """

  @behaviour Pristine.Ports.TokenSource

  alias Pristine.OAuth2.Token

  @impl true
  def fetch(opts) do
    case Keyword.get(opts, :token) do
      %Token{} = token -> {:ok, token}
      _other -> :error
    end
  end

  @impl true
  def put(_token, _opts), do: :ok
end
