defmodule Pristine.Adapters.Retry.FoundationCancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Adapters.Retry.Foundation
  alias Pristine.{Cancellation, Error}

  test "cancellation interrupts a pending retry delay and prevents the next attempt" do
    cancellation = Cancellation.new()
    parent = self()

    retry_task =
      Task.async(fn ->
        Foundation.with_retry(
          fn ->
            send(parent, :attempt_started)
            {:error, :retryable}
          end,
          cancellation: cancellation,
          max_attempts: 3,
          base_ms: 30_000,
          max_ms: 30_000,
          retry_on: fn _result -> true end,
          sleep_fun: fn _delay_ms ->
            send(parent, :retry_wait_started)
            Cancellation.await(cancellation, :infinity)
          end
        )
      end)

    assert_receive :attempt_started
    assert_receive :retry_wait_started

    assert :ok = Cancellation.cancel(cancellation)
    assert {:error, %Error{type: :cancelled}} = Task.await(retry_task)
    refute_received :attempt_started
  end
end
