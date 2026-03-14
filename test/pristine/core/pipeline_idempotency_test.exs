defmodule Pristine.Core.PipelineIdempotencyTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.{Context, EndpointMetadata, Pipeline}

  describe "idempotency header" do
    test "adds idempotency header when endpoint has idempotency: true" do
      request =
        Pipeline.build_request(endpoint(idempotency: true), "", "application/json", context(), [])

      assert Map.has_key?(request.headers, "X-Idempotency-Key")
      assert String.length(request.headers["X-Idempotency-Key"]) == 36
    end

    test "uses custom idempotency key from opts" do
      request =
        Pipeline.build_request(endpoint(idempotency: true), "", "application/json", context(),
          idempotency_key: "custom-key-123"
        )

      assert request.headers["X-Idempotency-Key"] == "custom-key-123"
    end

    test "does not add header when endpoint has idempotency: false" do
      request =
        Pipeline.build_request(
          endpoint(idempotency: false),
          "",
          "application/json",
          context(),
          []
        )

      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end

    test "does not add header when idempotency is nil (default)" do
      request = Pipeline.build_request(endpoint(), "", "application/json", context(), [])
      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end

    test "uses custom header name from context" do
      request =
        Pipeline.build_request(
          endpoint(idempotency: true),
          "",
          "application/json",
          %Context{context() | idempotency_header: "X-Request-Id"},
          []
        )

      assert Map.has_key?(request.headers, "X-Request-Id")
      refute Map.has_key?(request.headers, "X-Idempotency-Key")
    end
  end

  defp endpoint(overrides \\ []) do
    struct(
      EndpointMetadata,
      Keyword.merge(
        [
          id: "test",
          method: "POST",
          path: "/test",
          headers: %{},
          query: %{}
        ],
        overrides
      )
    )
  end

  defp context do
    %Context{
      base_url: "https://api.example.com",
      headers: %{},
      auth: [],
      idempotency_header: "X-Idempotency-Key"
    }
  end
end
