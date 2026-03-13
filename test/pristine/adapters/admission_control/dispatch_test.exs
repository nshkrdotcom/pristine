defmodule Pristine.Adapters.AdmissionControl.DispatchTest do
  use ExUnit.Case, async: true

  alias Foundation.Dispatch
  alias Foundation.RateLimit.BackoffWindow
  alias Foundation.Semaphore.Counting
  alias Pristine.Adapters.AdmissionControl.Dispatch, as: DispatchAdapter

  test "with_admission/2 accepts registered dispatch server handles" do
    registry = Counting.new_registry()
    rate_registry = BackoffWindow.new_registry()
    limiter = BackoffWindow.for_key(rate_registry, :dispatch_test)
    name = {:global, {__MODULE__, make_ref()}}

    {:ok, _pid} =
      Dispatch.start_link(
        name: name,
        key: :dispatch_test,
        registry: registry,
        limiter: limiter,
        concurrency: 2,
        throttled_concurrency: 1,
        byte_budget: 100,
        acquire_backoff: [base_ms: 1, max_ms: 1, jitter: 0]
      )

    snapshot = Dispatch.snapshot(name)
    parent = self()

    assert :ok =
             DispatchAdapter.with_admission(
               fn ->
                 send(
                   parent,
                   {:counts, Counting.count(registry, snapshot.concurrency.name)}
                 )

                 :ok
               end,
               dispatch: name,
               estimated_bytes: 10
             )

    assert_received {:counts, 1}
  end

  test "set_backoff/2 accepts registered dispatch server handles" do
    registry = Counting.new_registry()
    rate_registry = BackoffWindow.new_registry()
    limiter = BackoffWindow.for_key(rate_registry, :dispatch_backoff_test)
    name = {:global, {__MODULE__, make_ref()}}

    {:ok, _pid} =
      Dispatch.start_link(
        name: name,
        key: :dispatch_backoff_test,
        registry: registry,
        limiter: limiter,
        concurrency: 2,
        throttled_concurrency: 1,
        byte_budget: 100
      )

    refute Dispatch.snapshot(name).backoff_active?

    assert :ok = DispatchAdapter.set_backoff(100, dispatch: name)
    assert Dispatch.snapshot(name).backoff_active?
  end

  test "raises for invalid explicit dispatch configuration" do
    assert_raise ArgumentError, ~r/dispatch/i, fn ->
      DispatchAdapter.with_admission(fn -> :ok end, dispatch: :missing_dispatch)
    end

    assert_raise ArgumentError, ~r/dispatch/i, fn ->
      DispatchAdapter.set_backoff(100, dispatch: :missing_dispatch)
    end
  end
end
