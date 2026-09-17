defmodule Pristine.ErrorCancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Core.Response
  alias Pristine.Error

  test "cancellation has a dedicated non-retriable error type" do
    error = Error.cancelled_error()

    assert error.type == :cancelled
    assert Error.message(error) == "Request was cancelled"
    refute Error.retriable?(error)
  end

  test "cancellation cannot be made retriable by an HTTP retry header" do
    error = %Error{
      type: :cancelled,
      response: %Response{status: 499, headers: %{"x-should-retry" => "true"}, body: nil}
    }

    refute Error.retriable?(error)
  end
end
