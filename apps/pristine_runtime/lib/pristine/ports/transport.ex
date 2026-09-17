defmodule Pristine.Ports.Transport do
  @moduledoc """
  Transport boundary for sending requests.

  `send/2` remains the only required callback. Existing adapters that implement
  only `send/2` continue to support ordinary request execution.

  Adapters may additionally advertise provider-neutral runtime capabilities with
  `capabilities/1` and implement `send_cancelable/3`. Capability advertisement
  must be side-effect free. Absence or malformed advertisement is unverified,
  never implicit support.

  Implementing `send_cancelable/3` alone is not proof of physical cancellation;
  an adapter must only advertise cancellation capabilities that its owner has
  verified through the underlying transport stack.
  """

  alias Pristine.Cancellation
  alias Pristine.Core.{Context, Request, Response}

  @callback send(Request.t(), Context.t()) :: {:ok, Response.t()} | {:error, term()}

  @callback capabilities(Context.t()) :: map()

  @callback send_cancelable(Request.t(), Context.t(), Cancellation.t()) ::
              {:ok, Response.t()} | {:error, term()}

  @optional_callbacks capabilities: 1, send_cancelable: 3
end
