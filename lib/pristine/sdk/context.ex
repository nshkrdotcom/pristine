defmodule Pristine.SDK.Context do
  @moduledoc """
  SDK-facing runtime context contract.

  Provider SDKs should use this module and `Pristine.foundation_context/1`.
  `Pristine.Core.Context` remains an internal runtime detail.
  """

  alias Pristine.Core.Context, as: RuntimeContext

  @type t :: RuntimeContext.t()

  @spec new() :: t()
  def new, do: RuntimeContext.new()

  @spec new(keyword()) :: t()
  defdelegate new(opts), to: RuntimeContext
end
