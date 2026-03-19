defmodule Pristine.Examples.EchoPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/sampling" do
    body = Jason.encode!(conn.query_params)
    send_resp(conn, 200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

{:ok, _} = Finch.start_link(name: PristineFinch)

{:ok, _pid} =
  Plug.Cowboy.http(
    Pristine.Examples.EchoPlug,
    [],
    port: 4041
  )

client =
  Pristine.Client.new(
    base_url: "http://localhost:4041",
    transport: Pristine.Adapters.Transport.Finch,
    transport_opts: [finch: PristineFinch],
    serializer: Pristine.Adapters.Serializer.JSON,
    retry: Pristine.Adapters.Retry.Noop,
    telemetry: Pristine.Adapters.Telemetry.Noop
  )

operation =
  Pristine.Operation.new(%{
    id: "sample",
    method: :get,
    path_template: "/sampling",
    query: %{prompt: "hello", sampling: "none"},
    response_schemas: %{200 => nil}
  })

IO.inspect(Pristine.execute(client, operation), label: "Response")
