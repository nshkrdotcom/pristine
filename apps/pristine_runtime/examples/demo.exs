alias Pristine.Core.Context

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

context = %Context{
  base_url: "http://localhost:4041",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: PristineFinch],
  serializer: Pristine.Adapters.Serializer.JSON,
  retry: Pristine.Adapters.Retry.Noop,
  telemetry: Pristine.Adapters.Telemetry.Noop
}

request_spec = %{
  id: "sample",
  method: :get,
  path: "/sampling",
  path_params: %{},
  query: %{prompt: "hello", sampling: "none"},
  headers: %{},
  body: nil,
  form_data: nil,
  auth: nil,
  security: nil,
  request_schema: nil,
  response_schema: nil
}

IO.inspect(Pristine.execute_request(request_spec, context), label: "Response")
*** Delete File: /home/home/p/g/n/pristine/apps/pristine_runtime/test/fixtures/invalid_manifest.json
*** Delete File: /home/home/p/g/n/pristine/apps/pristine_runtime/test/fixtures/valid_manifest.json
