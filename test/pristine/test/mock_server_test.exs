defmodule Pristine.Test.MockServerTest do
  use ExUnit.Case, async: false

  alias Pristine.Manifest
  alias Pristine.Test.MockServer

  # Start a test Finch pool for HTTP requests
  setup_all do
    Application.ensure_all_started(:finch)

    children = [
      {Finch, name: MockServerFinch}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
    :ok
  end

  describe "start/2 and stop/1" do
    test "starts a mock server on specified port" do
      manifest = build_test_manifest()

      {:ok, server} = MockServer.start(manifest, port: 0)

      assert is_pid(server.pid)
      assert is_integer(server.port)
      assert server.port > 0

      MockServer.stop(server)
    end

    test "stop/1 shuts down the server" do
      manifest = build_test_manifest()
      {:ok, server} = MockServer.start(manifest, port: 0)

      :ok = MockServer.stop(server)

      # Server should no longer accept connections
      result = request(:get, "http://localhost:#{server.port}/test")
      assert {:error, _} = result
    end
  end

  describe "request handling" do
    test "server responds to GET requests" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}", response: "User"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      {:ok, response} = request(:get, "http://localhost:#{server.port}/users/123")

      assert response.status == 200
      assert {:ok, _body} = Jason.decode(response.body)

      MockServer.stop(server)
    end

    test "server responds to POST requests" do
      manifest =
        build_test_manifest_with_endpoints([
          %{
            id: "create_user",
            method: "POST",
            path: "/users",
            request: "UserCreate",
            response: "User"
          }
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      body = Jason.encode!(%{name: "Test"})

      {:ok, response} =
        request(
          :post,
          "http://localhost:#{server.port}/users",
          [{"content-type", "application/json"}],
          body
        )

      assert response.status == 201

      MockServer.stop(server)
    end

    test "server returns 404 for unknown endpoints" do
      manifest = build_test_manifest()

      {:ok, server} = MockServer.start(manifest, port: 0)

      {:ok, response} = request(:get, "http://localhost:#{server.port}/unknown/path")

      assert response.status == 404

      MockServer.stop(server)
    end

    test "server matches path parameters correctly" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_post", method: "GET", path: "/users/{user_id}/posts/{post_id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      {:ok, response} = request(:get, "http://localhost:#{server.port}/users/123/posts/456")

      assert response.status == 200

      MockServer.stop(server)
    end
  end

  describe "expect/3" do
    test "sets expected responses" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, "get_user", %{
        status: 200,
        body: %{id: "123", name: "Expected User"}
      })

      {:ok, response} = request(:get, "http://localhost:#{server.port}/users/123")

      body = Jason.decode!(response.body)
      assert body["name"] == "Expected User"

      MockServer.stop(server)
    end

    test "expectations are consumed in order" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, "get_user", %{body: %{name: "First"}})
      MockServer.expect(server, "get_user", %{body: %{name: "Second"}})

      {:ok, r1} = request(:get, "http://localhost:#{server.port}/users/1")
      {:ok, r2} = request(:get, "http://localhost:#{server.port}/users/2")

      assert Jason.decode!(r1.body)["name"] == "First"
      assert Jason.decode!(r2.body)["name"] == "Second"

      MockServer.stop(server)
    end

    test "falls back to generated fixture after expectations exhausted" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}", response: "User"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, "get_user", %{body: %{name: "Expected"}})

      # First request uses expectation
      {:ok, r1} = request(:get, "http://localhost:#{server.port}/users/1")
      assert Jason.decode!(r1.body)["name"] == "Expected"

      # Second request falls back to generated fixture
      {:ok, r2} = request(:get, "http://localhost:#{server.port}/users/2")
      assert is_map(Jason.decode!(r2.body))

      MockServer.stop(server)
    end
  end

  describe "verify!/1" do
    test "raises if expected calls were not made" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, "get_user", %{body: %{}})

      assert_raise RuntimeError, ~r/unfulfilled expectation/, fn ->
        MockServer.verify!(server)
      end

      MockServer.stop(server)
    end

    test "succeeds when all expectations fulfilled" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, "get_user", %{body: %{}})

      request(:get, "http://localhost:#{server.port}/users/123")

      assert :ok = MockServer.verify!(server)

      MockServer.stop(server)
    end
  end

  describe "history/1" do
    test "returns list of received requests" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "get_user", method: "GET", path: "/users/{id}"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      request(:get, "http://localhost:#{server.port}/users/123")
      request(:get, "http://localhost:#{server.port}/users/456")

      history = MockServer.history(server)

      assert length(history) == 2
      assert Enum.at(history, 0).path_params["id"] == "123"
      assert Enum.at(history, 1).path_params["id"] == "456"

      MockServer.stop(server)
    end

    test "records request method and path" do
      manifest =
        build_test_manifest_with_endpoints([
          %{id: "create_user", method: "POST", path: "/users"}
        ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      request(
        :post,
        "http://localhost:#{server.port}/users",
        [{"content-type", "application/json"}],
        "{}"
      )

      [req] = MockServer.history(server)

      assert req.method == "POST"
      assert req.path == "/users"

      MockServer.stop(server)
    end
  end

  # Helper functions

  defp request(method, url, headers \\ [], body \\ nil) do
    req = Finch.build(method, url, headers, body)

    case Finch.request(req, MockServerFinch, receive_timeout: 5000) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_test_manifest do
    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: [%{id: "test", method: "GET", path: "/test"}],
      types: %{
        "User" => %{
          fields: %{
            id: %{type: "string", required: true},
            name: %{type: "string", required: true}
          }
        }
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end

  defp build_test_manifest_with_endpoints(endpoints) do
    endpoint_defs =
      Enum.map(endpoints, fn ep ->
        %{
          id: ep[:id],
          method: ep[:method],
          path: ep[:path],
          request: ep[:request],
          response: ep[:response]
        }
      end)

    input = %{
      name: "TestAPI",
      version: "1.0.0",
      endpoints: endpoint_defs,
      types: %{
        "User" => %{
          fields: %{
            id: %{type: "string", required: true},
            name: %{type: "string", required: true}
          }
        },
        "UserCreate" => %{
          fields: %{
            name: %{type: "string", required: true}
          }
        }
      }
    }

    {:ok, manifest} = Manifest.load(input)
    manifest
  end
end
