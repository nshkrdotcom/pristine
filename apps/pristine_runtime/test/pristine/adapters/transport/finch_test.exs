defmodule Pristine.Adapters.Transport.FinchTest do
  use ExUnit.Case, async: false

  @compile {:no_warn_undefined, [Bandit, ThousandIsland]}
  @socket_skip (case :gen_tcp.listen(0, [
                       :binary,
                       active: false,
                       ip: {127, 0, 0, 1},
                       reuseaddr: true
                     ]) do
                  {:ok, socket} ->
                    :gen_tcp.close(socket)
                    nil

                  {:error, reason} ->
                    "loopback sockets unavailable in this environment: #{inspect(reason)}"
                end)
  @moduletag skip: @socket_skip

  alias ExecutionPlane.Contracts.Failure
  alias Pristine.Adapters.Transport.Finch, as: FinchTransport
  alias Pristine.Core.{Context, Request}

  defmodule SlowPlug do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/slow" do
      Process.sleep(150)
      send_resp(conn, 200, "ok")
    end
  end

  setup do
    {:ok, server_pid} =
      Bandit.start_link(
        plug: SlowPlug,
        port: 0,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server_pid)

    on_exit(fn ->
      stop_supervised_pid(server_pid)
    end)

    {:ok, port: port}
  end

  test "send/2 classifies unary transport timeouts through the execution plane", %{port: port} do
    request = %Request{
      method: "GET",
      url: "http://localhost:#{port}/slow",
      headers: %{},
      metadata: %{timeout: 10}
    }

    context = %Context{}

    assert {:error, {:execution_plane_transport, %Failure{} = failure, _raw_payload}} =
             FinchTransport.send(request, context)

    assert failure.retryable? == true
  end

  test "send/2 returns semantic HTTP responses through the execution plane", %{port: port} do
    request = %Request{
      method: "GET",
      url: "http://localhost:#{port}/slow",
      headers: %{},
      metadata: %{pool_name: nil, timeout: 500}
    }

    context = %Context{}

    assert {:ok, response} = FinchTransport.send(request, context)
    assert response.status == 200
    assert response.body == "ok"
  end

  defp stop_supervised_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        Supervisor.stop(pid, :normal)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
