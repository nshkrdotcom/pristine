defmodule Pristine.Adapters.Transport.FinchStreamTest do
  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, [Bandit, ThousandIsland]}

  alias Pristine.Adapters.Transport.FinchStream
  alias Pristine.Core.{Context, Request}
  alias Pristine.Streaming.Event

  defmodule SlowStreamPlug do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/slow" do
      Process.sleep(150)

      conn
      |> put_resp_content_type("text/event-stream")
      |> send_resp(200, "data: hello\n\n")
    end
  end

  describe "decode_sse_body/1" do
    test "decodes SSE body into events" do
      body = "event: message\ndata: {\"foo\":\"bar\"}\n\ndata: second\n\n"

      events = FinchStream.decode_sse_body(body)

      assert length(events) == 2
      assert Enum.at(events, 0).event == "message"
      assert Enum.at(events, 0).data == ~s({"foo":"bar"})
      assert Enum.at(events, 1).data == "second"
    end

    test "decodes body with multi-line data" do
      body = "data: line1\ndata: line2\ndata: line3\n\n"

      [event] = FinchStream.decode_sse_body(body)

      assert event.data == "line1\nline2\nline3"
    end

    test "handles empty body" do
      events = FinchStream.decode_sse_body("")

      # Empty body produces no events (empty events are filtered out)
      assert events == []
    end

    test "decodes body with all SSE fields" do
      body = "event: update\nid: evt_123\nretry: 5000\ndata: payload\n\n"

      [event] = FinchStream.decode_sse_body(body)

      assert event.event == "update"
      assert event.id == "evt_123"
      assert event.retry == 5000
      assert event.data == "payload"
    end

    test "ignores comment lines" do
      body = ": this is a comment\ndata: real_data\n\n"

      [event] = FinchStream.decode_sse_body(body)

      assert event.data == "real_data"
    end

    test "handles incomplete event at end" do
      # Body without trailing \n\n - we add it in decode_sse_body
      body = "data: complete\n\ndata: incomplete"

      events = FinchStream.decode_sse_body(body)

      assert length(events) == 2
      assert Enum.at(events, 0).data == "complete"
      assert Enum.at(events, 1).data == "incomplete"
    end
  end

  describe "decode_sse_body/1 with JSON parsing" do
    test "events can be parsed as JSON" do
      body = "data: {\"key\": \"value\"}\n\n"

      [event] = FinchStream.decode_sse_body(body)

      assert {:ok, %{"key" => "value"}} = Event.json(event)
    end

    test "events can be parsed with json!/1" do
      body = "data: {\"n\": 42}\n\n"

      [event] = FinchStream.decode_sse_body(body)

      assert %{"n" => 42} = Event.json!(event)
    end
  end

  describe "stream/2 timeout handling" do
    test "uses request timeout metadata when opening the stream" do
      finch_name = :"pristine_stream_finch_#{System.unique_integer([:positive])}"
      {:ok, finch_pid} = Finch.start_link(name: finch_name)

      {:ok, server_pid} =
        Bandit.start_link(
          plug: SlowStreamPlug,
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

      request = %Request{
        method: "GET",
        url: "http://localhost:#{port}/slow",
        headers: %{},
        metadata: %{timeout: 10}
      }

      context = %Context{transport_opts: [finch: finch_name]}

      assert {:error, :timeout} = FinchStream.stream(request, context)
    end
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
