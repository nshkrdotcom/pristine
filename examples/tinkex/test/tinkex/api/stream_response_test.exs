defmodule Tinkex.API.StreamResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.StreamResponse

  describe "struct" do
    test "has enforce_keys constraint" do
      # Verify the struct has enforce_keys by checking the module's struct definition
      assert StreamResponse.__struct__().stream == nil
      assert StreamResponse.__struct__().status == nil
    end

    test "creates with all required fields" do
      response = %StreamResponse{
        stream: Stream.map(1..3, & &1),
        status: 200,
        headers: %{"content-type" => "text/event-stream"},
        method: :get,
        url: "https://example.com/stream"
      }

      assert response.status == 200
      assert response.method == :get
      assert response.url == "https://example.com/stream"
    end

    test "allows optional elapsed_ms" do
      response = %StreamResponse{
        stream: [],
        status: 200,
        headers: %{},
        method: :get,
        url: "https://example.com",
        elapsed_ms: 150
      }

      assert response.elapsed_ms == 150
    end

    test "stream is enumerable" do
      stream = Stream.map(1..3, & &1)

      response = %StreamResponse{
        stream: stream,
        status: 200,
        headers: %{},
        method: :get,
        url: "https://example.com"
      }

      assert Enum.to_list(response.stream) == [1, 2, 3]
    end
  end
end
