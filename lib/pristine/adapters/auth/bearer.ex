defmodule Pristine.Adapters.Auth.Bearer do
  @moduledoc """
  Bearer token auth adapter.
  """

  @behaviour Pristine.Ports.Auth

  @doc """
  Build a bearer auth tuple for Context auth configuration.
  """
  @spec new(String.t(), keyword()) :: {module(), keyword()}
  def new(token, opts \\ []) when is_list(opts) do
    {__MODULE__, Keyword.put(opts, :token, token)}
  end

  @impl true
  def headers(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} -> {:ok, %{"Authorization" => "Bearer #{token}"}}
      :error -> {:error, :missing_bearer_token}
    end
  end
end
