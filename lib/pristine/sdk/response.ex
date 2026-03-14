defmodule Pristine.SDK.Response do
  @moduledoc """
  SDK-facing helper for constructing normalized transport responses.
  """

  alias Pristine.Core.Response, as: RuntimeResponse

  @type t :: RuntimeResponse.t()

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    struct(RuntimeResponse, opts)
  end
end
