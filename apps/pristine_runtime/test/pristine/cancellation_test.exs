defmodule Pristine.CancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Cancellation

  test "new tokens are active and cancellation is terminal and idempotent" do
    cancellation = Cancellation.new()

    refute Cancellation.cancelled?(cancellation)
    assert :ok = Cancellation.cancel(cancellation)
    assert Cancellation.cancelled?(cancellation)
    assert :ok = Cancellation.cancel(cancellation)
    assert Cancellation.cancelled?(cancellation)
  end

  test "concurrent cancellation is safe" do
    cancellation = Cancellation.new()

    tasks =
      for _ <- 1..16 do
        Task.async(fn -> Cancellation.cancel(cancellation) end)
      end

    assert Enum.all?(Task.await_many(tasks), &(&1 == :ok))
    assert Cancellation.cancelled?(cancellation)
  end

  test "await wakes when another process cancels the token" do
    cancellation = Cancellation.new()
    parent = self()

    waiter =
      Task.async(fn ->
        send(parent, :waiter_started)
        Cancellation.await(cancellation, :infinity)
      end)

    assert_receive :waiter_started
    assert :ok = Cancellation.cancel(cancellation)
    assert :cancelled = Task.await(waiter)
  end

  test "timed-out wait unregisters its Registry subscription" do
    cancellation = Cancellation.new()

    assert :timeout = Cancellation.await(cancellation, 0)
    assert Registry.keys(Pristine.Cancellation.Registry, self()) == []
  end

  test "inspect does not expose atomics or token identifiers" do
    cancellation = Cancellation.new()
    rendered = inspect(cancellation)

    refute rendered =~ "state"
    refute rendered =~ "id:"
  end
end
