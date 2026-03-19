defmodule Pristine.Adapters.Auth.ApiKey do
  @moduledoc """
  Static API key auth adapter.
  """

  @behaviour Pristine.Ports.Auth

  @doc """
  Build an API key auth tuple for Context auth configuration.
  """
  @spec new(String.t(), keyword()) :: {module(), keyword()}
  def new(value, opts \\ []) when is_list(opts) do
    {__MODULE__, Keyword.put(opts, :value, value)}
  end

  @impl true
  def headers(opts) do
    header = Keyword.get(opts, :header, "X-API-Key")

    case Keyword.fetch(opts, :value) do
      {:ok, value} -> {:ok, %{header => value}}
      :error -> {:error, :missing_api_key}
    end
  end
end
