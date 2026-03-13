defmodule Pristine.Adapters.Transport.FinchTest do
  use ExUnit.Case, async: false

  @compile {:no_warn_undefined, [Bandit, ThousandIsland]}

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
    finch_name = :"pristine_finch_#{System.unique_integer([:positive])}"
    {:ok, finch_pid} = Finch.start_link(name: finch_name)

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

      if Process.alive?(finch_pid) do
        Process.exit(finch_pid, :normal)
      end
    end)

    {:ok, finch: finch_name, port: port}
  end

  test "send/2 forwards request timeout to Finch", %{finch: finch, port: port} do
    request = %Request{
      method: "GET",
      url: "http://localhost:#{port}/slow",
      headers: %{},
      metadata: %{timeout: 10}
    }

    context = %Context{transport_opts: [finch: finch]}

    assert {:error, reason} = FinchTransport.send(request, context)
    assert String.contains?(inspect(reason), "timeout")
  end

  test "send/2 falls back to the configured Finch instance when metadata pool_name is nil", %{
    finch: finch,
    port: port
  } do
    request = %Request{
      method: "GET",
      url: "http://localhost:#{port}/slow",
      headers: %{},
      metadata: %{pool_name: nil, timeout: 500}
    }

    context = %Context{transport_opts: [finch: finch]}

    assert {:ok, response} = FinchTransport.send(request, context)
    assert response.status == 200
    assert response.body == "ok"
  end

  test "request/5 falls back to the configured Finch instance when opts pool_name is nil", %{
    finch: finch,
    port: port
  } do
    assert {:ok, response} =
             FinchTransport.request(:get, "http://localhost:#{port}/slow", [], nil,
               finch: finch,
               pool_name: nil,
               receive_timeout: 500
             )

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
