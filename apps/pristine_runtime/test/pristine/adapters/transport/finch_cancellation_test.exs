defmodule Pristine.Adapters.Transport.FinchCancellationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Pristine.Adapters.{CircuitBreaker, RateLimit, Retry, Serializer}
  alias Pristine.Adapters.Transport.Finch
  alias Pristine.{Cancellation, Error}
  alias Pristine.Core.Context

  @request %{id: "physical-cancellation", method: :get, path: "/hold"}

  test "pipeline cancellation closes the real HTTP socket and cleans up its processes" do
    {server, endpoint} = server()
    token = Cancellation.new()
    task = Task.async(fn -> execute(endpoint, token) end)
    assert_receive {:accepted, ^server}, 2_000
    watchers = wait_for_watchers(token)
    assert [{watcher, _subscription}] = watchers
    watcher_monitor = Process.monitor(watcher)

    cancel = Task.async(fn -> Cancellation.cancel(token) end)
    assert :ok = Task.await(cancel)
    assert {:error, %Error{type: :cancelled}} = Task.await(task)
    assert_receive {:closed, ^server, {:error, :closed}}, 2_000
    assert_receive {:late_write, ^server, {:error, _}}, 2_000
    assert_receive {:DOWN, ^watcher_monitor, :process, ^watcher, _}
    assert Registry.lookup(Pristine.Cancellation.Registry, token.id) == []
    ref = task.ref
    refute_receive {^ref, {:ok, _}}
    assert :ok = Cancellation.cancel(token)
  end

  test "normal completion wins and leaves no cancellation watcher" do
    {server, endpoint} = server()
    token = Cancellation.new()
    task = Task.async(fn -> execute(endpoint, token) end)
    assert_receive {:accepted, ^server}, 2_000
    send(server, :respond)
    assert {:ok, _} = Task.await(task)
    assert Registry.lookup(Pristine.Cancellation.Registry, token.id) == []
    assert :ok = Cancellation.cancel(token)
    ref = task.ref
    refute_receive {^ref, _}
  end

  test "caller death closes the physical socket and removes cancellation watchers" do
    {server, endpoint} = server()
    token = Cancellation.new()
    caller = spawn(fn -> execute(endpoint, token) end)
    on_exit(fn -> if Process.alive?(caller), do: Process.exit(caller, :kill) end)
    assert_receive {:accepted, ^server}, 2_000
    [{watcher, _}] = wait_for_watchers(token)
    monitor = Process.monitor(watcher)
    Process.exit(caller, :kill)
    assert_receive {:closed, ^server, {:error, :closed}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^watcher, _}, 2_000
    assert Registry.lookup(Pristine.Cancellation.Registry, token.id) == []
  end

  defp wait_for_watchers(token, attempts \\ 1_000) do
    case Registry.lookup(Pristine.Cancellation.Registry, token.id) do
      [] when attempts > 0 ->
        receive do
        after
          1 -> wait_for_watchers(token, attempts - 1)
        end

      watchers ->
        watchers
    end
  end

  defp execute(endpoint, token) do
    context =
      Context.new(
        base_url: endpoint,
        serializer: Serializer.JSON,
        transport: Finch,
        retry: Retry.Noop,
        rate_limiter: RateLimit.Noop,
        circuit_breaker: CircuitBreaker.Noop
      )

    Pristine.execute_request(@request, context, cancellation: token)
  end

  defp server do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 2_000)
        :ok = :inet.setopts(socket, active: :once)
        send(parent, {:accepted, self()})

        receive do
          :respond ->
            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\n{}"
              )

          {:tcp_closed, ^socket} ->
            send(parent, {:closed, self(), {:error, :closed}})
            send(parent, {:late_write, self(), :gen_tcp.send(socket, "late")})
        after
          5_000 -> raise "HTTP socket was neither cancelled nor completed"
        end

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    {pid, "http://127.0.0.1:#{port}"}
  end
end
