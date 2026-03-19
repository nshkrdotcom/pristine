defmodule Pristine.SDK.OAuth2.Error do
  @moduledoc """
  SDK-facing OAuth2 error contract.
  """

  alias Pristine.OAuth2.Error, as: RuntimeError

  @type t :: RuntimeError.t()

  @spec new(atom(), keyword()) :: t()
  defdelegate new(reason, opts \\ []), to: RuntimeError
end
