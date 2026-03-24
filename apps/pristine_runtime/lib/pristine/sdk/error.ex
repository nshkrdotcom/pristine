defmodule Pristine.SDK.Error do
  @moduledoc """
  SDK-facing error contract for request execution.
  """

  alias Pristine.Error, as: RuntimeError

  @type error_type :: RuntimeError.error_type()
  @type t :: RuntimeError.t()

  @spec from_response(Pristine.SDK.Response.t()) :: t()
  defdelegate from_response(response), to: RuntimeError

  @spec from_response(Pristine.SDK.Response.t(), keyword()) :: t()
  defdelegate from_response(response, opts), to: RuntimeError

  @spec connection_error(term()) :: t()
  defdelegate connection_error(reason), to: RuntimeError

  @spec connection_error(term(), keyword()) :: t()
  defdelegate connection_error(reason, opts), to: RuntimeError

  @spec validation_error(term(), term(), keyword()) :: t()
  defdelegate validation_error(reason, body, opts), to: RuntimeError

  @spec timeout_error() :: t()
  defdelegate timeout_error(), to: RuntimeError

  @spec message(t()) :: String.t()
  defdelegate message(error), to: RuntimeError

  @spec retriable?(t()) :: boolean()
  defdelegate retriable?(error), to: RuntimeError
end
