alias Pristine.Core.Context

defmodule Pristine.Examples.EchoPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/sampling" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
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

manifest = %{
  name: "demo",
  version: "0.1.0",
  endpoints: [
    %{
      id: "sample",
      method: "POST",
      path: "/sampling",
      request: "SampleRequest",
      response: "SampleResponse"
    }
  ],
  types: %{
    "SampleRequest" => %{
      fields: %{
        prompt: %{type: "string", required: true},
        sampling_params: %{type: "string", required: true}
      }
    },
    "SampleResponse" => %{
      fields: %{
        text: %{type: "string", required: true}
      }
    }
  }
}

context = %Context{
  base_url: "http://localhost:4041",
  transport: Pristine.Adapters.Transport.Finch,
  transport_opts: [finch: PristineFinch],
  serializer: Pristine.Adapters.Serializer.JSON,
  retry: Pristine.Adapters.Retry.Noop,
  telemetry: Pristine.Adapters.Telemetry.Noop
}

payload = %{prompt: "hello", sampling_params: "none"}

IO.inspect(Pristine.execute(manifest, "sample", payload, context), label: "Response")
