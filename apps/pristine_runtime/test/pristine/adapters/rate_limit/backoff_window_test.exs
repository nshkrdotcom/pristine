defmodule Pristine.Adapters.RateLimit.BackoffWindowTest do
  use ExUnit.Case, async: true

  alias Foundation.RateLimit.BackoffWindow, as: Window
  alias Pristine.Adapters.RateLimit.BackoffWindow, as: Adapter

  test "an explicit caller-owned table without an heir preserves its backoff" do
    registry = Window.new_registry()
    assert :ets.info(registry, :heir) == :none
    limiter = Window.for_key(registry, :request)
    :ok = Window.set(limiter, 123, time_fun: fn _ -> 1_000 end)
    assert Adapter.for_key(:request, registry: registry) == limiter

    parent = self()
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 1_000)

    assert :executed =
             Adapter.within_limit(fn -> :executed end,
               registry: registry,
               key: :request,
               time_fun: fn _ -> :atomics.get(clock, 1) end,
               sleep_fun: fn delay ->
                 send(parent, {:slept, delay})
                 :atomics.add(clock, 1, delay)
               end
             )

    assert_receive {:slept, 123}
    assert :ets.info(registry, :owner) == self()
  end

  test "short-lived callers share Foundation's supervised default table" do
    registry = Window.default_registry()
    key = make_ref()
    limiter = Adapter.for_key(key)
    parent = self()
    {worker, ref} = spawn_monitor(fn -> send(parent, {:limiter, Adapter.for_key(key)}) end)
    assert_receive {:limiter, ^limiter}
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    assert Window.default_registry() == registry
    assert :ets.info(registry, :owner) == Process.whereis(Foundation.Internal.RegistryOwner)
    assert :ets.info(registry, :heir) == :none
  end

  test "a deleted anonymous registry fails instead of silently bypassing limits" do
    registry = Window.new_registry()
    :ets.delete(registry)
    assert_raise ArgumentError, fn -> Adapter.for_key(:request, registry: registry) end
  end
end
