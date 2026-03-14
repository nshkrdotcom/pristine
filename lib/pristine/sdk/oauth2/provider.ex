defmodule Pristine.SDK.OAuth2.Provider do
  @moduledoc """
  SDK-facing OAuth2 provider configuration contract.
  """

  alias Pristine.OAuth2.Provider, as: RuntimeProvider

  @type t :: RuntimeProvider.t()

  @spec new(keyword()) :: t()
  defdelegate new(opts \\ []), to: RuntimeProvider

  @spec from_security_scheme(String.t() | atom(), map(), keyword()) ::
          {:ok, t()} | {:error, Pristine.SDK.OAuth2.Error.t()}
  defdelegate from_security_scheme(scheme_name, scheme, opts \\ []), to: RuntimeProvider

  @spec from_security_scheme!(String.t() | atom(), map(), keyword()) :: t()
  defdelegate from_security_scheme!(scheme_name, scheme, opts \\ []), to: RuntimeProvider
end
