defmodule Pristine.Adapters.Auth.GovernedCredential do
  @moduledoc """
  Governed auth adapter backed by `Pristine.GovernedAuthority`.
  """

  @behaviour Pristine.Ports.Auth

  alias Pristine.GovernedAuthority

  @doc """
  Build a governed credential auth tuple for context auth configuration.
  """
  @spec new(GovernedAuthority.t()) :: {module(), keyword()}
  def new(%GovernedAuthority{} = authority) do
    {__MODULE__, authority: authority}
  end

  @impl true
  def headers(opts) do
    case Keyword.get(opts, :authority) do
      %GovernedAuthority{credential_headers: headers} when map_size(headers) > 0 ->
        {:ok, headers}

      _other ->
        {:error, :missing_governed_authority}
    end
  end
end
