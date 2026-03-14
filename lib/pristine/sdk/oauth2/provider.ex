defmodule Pristine.SDK.OAuth2.Provider do
  @moduledoc """
  SDK-facing OAuth2 provider configuration contract.
  """

  alias Pristine.Manifest
  alias Pristine.OAuth2.Provider, as: RuntimeProvider

  @type t :: RuntimeProvider.t()

  @spec new(keyword()) :: t()
  defdelegate new(opts \\ []), to: RuntimeProvider

  @spec from_manifest(Manifest.t(), String.t() | atom()) ::
          {:ok, t()} | {:error, Pristine.SDK.OAuth2.Error.t()}
  defdelegate from_manifest(manifest, scheme_name), to: RuntimeProvider

  @spec from_manifest!(Manifest.t(), String.t() | atom()) :: t()
  defdelegate from_manifest!(manifest, scheme_name), to: RuntimeProvider
end
