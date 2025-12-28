defmodule Pristine.Core.PipelineIdempotencyTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.{Context, Pipeline}
  alias Pristine.Manifest.Endpoint

  describe "idempotency header" do
    test "adds idempotency header when endpoint has idempotency: true" do
      endpoint = %Endpoint{
        id: "test",
        method: "POST",
        path: "/test",
        idempotency: true,
        headers: %{},
        query: %{}
      }

      context = %Context{
        base_url: "https://api.example.com",
        headers: %{},
        auth: [],
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, "", "application/json", context, [])

      assert Map.has_key?(request.headers, "X-Idempotency-Key")
      # Should be a UUID (36 characters including hyphens)
      assert String.length(request.headers["X-Idempotency-Key"]) == 36
    end

    test "uses custom idempotency key from opts" do
      endpoint = %Endpoint{
        id: "test",
        method: "POST",
        path: "/test",
        idempotency: true,
        headers: %{},
        query: %{}
      }

      context = %Context{
        base_url: "https://api.example.com",
        headers: %{},
        auth: [],
        idempotency_header: "X-Idempotency-Key"
      }

      request =
        Pipeline.build_request(endpoint, "", "application/json", context,
          idempotency_key: "custom-key-123"
        )

      assert request.headers["X-Idempotency-Key"] == "custom-key-123"
    end

    test "does not add header when endpoint has idempotency: false" do
      endpoint = %Endpoint{
        id: "test",
        method: "POST",
        path: "/test",
        idempotency: false,
        headers: %{},
        query: %{}
      }

      context = %Context{
        base_url: "https://api.example.com",
        headers: %{},
        auth: [],
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, "", "application/json", context, [])

      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end

    test "does not add header when idempotency is nil (default)" do
      endpoint = %Endpoint{
        id: "test",
        method: "POST",
        path: "/test",
        headers: %{},
        query: %{}
      }

      context = %Context{
        base_url: "https://api.example.com",
        headers: %{},
        auth: [],
        idempotency_header: "X-Idempotency-Key"
      }

      request = Pipeline.build_request(endpoint, "", "application/json", context, [])

      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end

    test "uses custom header name from context" do
      endpoint = %Endpoint{
        id: "test",
        method: "POST",
        path: "/test",
        idempotency: true,
        headers: %{},
        query: %{}
      }

      context = %Context{
        base_url: "https://api.example.com",
        headers: %{},
        auth: [],
        idempotency_header: "X-Request-Id"
      }

      request = Pipeline.build_request(endpoint, "", "application/json", context, [])

      assert Map.has_key?(request.headers, "X-Request-Id")
      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end
  end
end
