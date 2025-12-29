defmodule Integration.TinkexMockTest do
  @moduledoc """
  Integration tests for the Tinkex example using mocked transport.

  Tests the full flow of making requests with mocked responses,
  validating that the manifest-driven pipeline works correctly.
  """

  use ExUnit.Case, async: true

  import Mox

  alias Pristine.Core.Context
  alias Pristine.Core.Pipeline
  alias Pristine.Core.Response
  alias Pristine.Error
  alias Pristine.Manifest

  @manifest_path "examples/tinkex/manifest.json"

  # Allow mocks to be used in async tests
  setup :verify_on_exit!

  setup do
    {:ok, manifest} = Manifest.load_file(@manifest_path)

    context =
      Context.new(
        base_url: "https://api.tinker.ai/v1",
        transport: Pristine.TransportMock,
        serializer: Pristine.Adapters.Serializer.JSON,
        # Use noop adapters for resilience in tests
        retry: Pristine.Adapters.Retry.Noop,
        rate_limiter: Pristine.Adapters.RateLimit.Noop,
        circuit_breaker: Pristine.CircuitBreakerMock
      )

    # Set up a pass-through circuit breaker mock
    stub(Pristine.CircuitBreakerMock, :call, fn _name, fun, _opts -> fun.() end)

    {:ok, manifest: manifest, context: context}
  end

  describe "models resource" do
    test "list_models returns model list", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          data: [
            %{id: "model-1", name: "Test Model 1", context_length: 4096},
            %{id: "model-2", name: "Test Model 2", context_length: 8192}
          ],
          has_more: false
        })

      expect(Pristine.TransportMock, :send, fn request, _context ->
        assert request.method == "GET"
        assert request.url =~ "/models"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      {:ok, result} = Pipeline.execute(manifest, "list_models", %{}, context)

      assert is_map(result)
      assert is_list(result["data"])
      assert length(result["data"]) == 2
      assert Enum.at(result["data"], 0)["id"] == "model-1"
    end

    test "get_model returns single model", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          id: "model-1",
          name: "Test Model",
          description: "A test model",
          context_length: 4096,
          capabilities: ["text", "code"]
        })

      expect(Pristine.TransportMock, :send, fn request, _context ->
        assert request.method == "GET"
        assert request.url =~ "/models/model-1"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      {:ok, model} =
        Pipeline.execute(manifest, "get_model", %{}, context,
          path_params: %{"model_id" => "model-1"}
        )

      assert model["id"] == "model-1"
      assert model["name"] == "Test Model"
      assert "text" in model["capabilities"]
    end

    test "get_model returns 404 error body for unknown model", %{
      manifest: manifest,
      context: context
    } do
      response_body =
        Jason.encode!(%{
          type: "not_found_error",
          message: "Model not found"
        })

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Response{
           status: 404,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      assert {:error, %Error{} = error} =
               Pipeline.execute(manifest, "get_model", %{}, context,
                 path_params: %{"model_id" => "unknown"}
               )

      assert error.type == :not_found
      assert error.status == 404
      assert error.body["type"] == "not_found_error"
      assert error.body["message"] == "Model not found"
    end
  end

  describe "sampling resource" do
    test "create_sample returns sample result", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          id: "sample-123",
          model: "model-1",
          content: [%{type: "text", text: "Hello, world!"}],
          stop_reason: "end_turn",
          usage: %{input_tokens: 10, output_tokens: 5},
          created_at: "2025-01-01T00:00:00Z"
        })

      expect(Pristine.TransportMock, :send, fn request, _context ->
        assert request.method == "POST"
        assert request.url =~ "/samples"

        # Verify request body was encoded
        body = Jason.decode!(request.body)
        assert body["model"] == "model-1"
        assert body["prompt"] == "Hello"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      request = %{
        model: "model-1",
        prompt: "Hello",
        max_tokens: 100
      }

      {:ok, result} = Pipeline.execute(manifest, "create_sample", request, context)

      assert result["id"] == "sample-123"
      assert length(result["content"]) == 1
      assert result["stop_reason"] == "end_turn"
    end

    test "get_sample retrieves existing sample", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          id: "sample-123",
          model: "model-1",
          content: [%{type: "text", text: "Previously generated text"}],
          stop_reason: "end_turn",
          usage: %{input_tokens: 10, output_tokens: 25},
          created_at: "2025-01-01T00:00:00Z"
        })

      expect(Pristine.TransportMock, :send, fn request, _context ->
        assert request.method == "GET"
        assert request.url =~ "/samples/sample-123"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      {:ok, result} =
        Pipeline.execute(manifest, "get_sample", %{}, context,
          path_params: %{"sample_id" => "sample-123"}
        )

      assert result["id"] == "sample-123"
    end

    test "create_sample_async returns async response", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          id: "sample-async-1",
          status: "pending",
          poll_url: "/samples/sample-async-1"
        })

      expect(Pristine.TransportMock, :send, fn request, _context ->
        assert request.method == "POST"
        assert request.url =~ "/samples/async"

        {:ok,
         %Response{
           status: 202,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      request = %{
        model: "model-1",
        prompt: "Long running request"
      }

      {:ok, result} = Pipeline.execute(manifest, "create_sample_async", request, context)

      assert result["id"] == "sample-async-1"
      assert result["status"] == "pending"
      assert result["poll_url"] =~ "/samples/"
    end
  end

  describe "error handling" do
    test "rate limit response includes error details", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          type: "rate_limit_error",
          message: "Rate limit exceeded"
        })

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Response{
           status: 429,
           headers: [{"retry-after", "30"}, {"content-type", "application/json"}],
           body: response_body
         }}
      end)

      request = %{model: "m1", prompt: "test"}

      assert {:error, %Error{} = error} =
               Pipeline.execute(manifest, "create_sample", request, context)

      assert error.type == :rate_limit
      assert error.status == 429
      assert error.body["type"] == "rate_limit_error"
      assert error.body["message"] == "Rate limit exceeded"
    end

    test "authentication error response includes error type", %{
      manifest: manifest,
      context: context
    } do
      response_body =
        Jason.encode!(%{
          type: "authentication_error",
          message: "Invalid API key"
        })

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Response{
           status: 401,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      assert {:error, %Error{} = error} = Pipeline.execute(manifest, "list_models", %{}, context)
      assert error.type == :authentication
      assert error.status == 401
      assert error.body["type"] == "authentication_error"
    end

    test "server error response includes error details", %{manifest: manifest, context: context} do
      response_body =
        Jason.encode!(%{
          type: "api_error",
          message: "Internal server error"
        })

      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:ok,
         %Response{
           status: 500,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      assert {:error, %Error{} = error} = Pipeline.execute(manifest, "list_models", %{}, context)
      assert error.type == :internal_server
      assert error.status == 500
      assert error.body["type"] == "api_error"
      assert error.body["message"] == "Internal server error"
    end

    test "transport errors propagate correctly", %{manifest: manifest, context: context} do
      expect(Pristine.TransportMock, :send, fn _request, _context ->
        {:error, :connection_refused}
      end)

      {:error, error} = Pipeline.execute(manifest, "list_models", %{}, context)
      assert error == :connection_refused
    end
  end

  describe "idempotency" do
    test "idempotent endpoint includes idempotency header", %{
      manifest: manifest,
      context: context
    } do
      response_body = Jason.encode!(%{id: "sample-1"})

      expect(Pristine.TransportMock, :send, fn request, _context ->
        # Verify idempotency header was sent
        assert Map.get(request.headers, "X-Idempotency-Key") == "unique-key-123"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      request = %{model: "model-1", prompt: "Test"}

      {:ok, _} =
        Pipeline.execute(manifest, "create_sample", request, context,
          idempotency_key: "unique-key-123"
        )
    end
  end

  describe "request building" do
    test "path parameters are substituted correctly", %{manifest: manifest, context: context} do
      response_body = Jason.encode!(%{id: "my-model-id", name: "Test"})

      expect(Pristine.TransportMock, :send, fn request, _context ->
        # Verify the path parameter was substituted
        assert request.url =~ "/models/my-model-id"
        refute request.url =~ "{model_id}"

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      {:ok, _} =
        Pipeline.execute(manifest, "get_model", %{}, context,
          path_params: %{"model_id" => "my-model-id"}
        )
    end

    test "request body is serialized as JSON", %{manifest: manifest, context: context} do
      response_body = Jason.encode!(%{id: "sample-1"})

      expect(Pristine.TransportMock, :send, fn request, _context ->
        # Verify body is valid JSON
        body = Jason.decode!(request.body)
        assert is_map(body)
        assert body["model"] == "test-model"
        assert body["prompt"] == "Hello world"
        assert body["max_tokens"] == 50

        {:ok,
         %Response{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: response_body
         }}
      end)

      request = %{
        model: "test-model",
        prompt: "Hello world",
        max_tokens: 50
      }

      {:ok, _} = Pipeline.execute(manifest, "create_sample", request, context)
    end
  end
end
