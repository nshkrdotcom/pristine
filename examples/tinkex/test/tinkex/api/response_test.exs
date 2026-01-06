defmodule Tinkex.API.ResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Response

  describe "new/2" do
    test "creates response from Finch response" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: ~s({"key": "value"})
      }

      result = Response.new(finch_response, method: :get, url: "https://example.com")

      assert result.status == 200
      assert result.method == :get
      assert result.url == "https://example.com"
      assert result.body == ~s({"key": "value"})
      assert result.data == %{"key" => "value"}
    end

    test "normalizes headers to lowercase keys" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [{"Content-Type", "application/json"}, {"X-Custom", "value"}],
        body: "{}"
      }

      result = Response.new(finch_response, method: :get, url: "https://example.com")

      assert result.headers["content-type"] == "application/json"
      assert result.headers["x-custom"] == "value"
    end

    test "sets elapsed_ms and retries from opts" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: "{}"
      }

      result =
        Response.new(finch_response,
          method: :get,
          url: "https://example.com",
          elapsed_ms: 150,
          retries: 2
        )

      assert result.elapsed_ms == 150
      assert result.retries == 2
    end

    test "defaults elapsed_ms to 0 and retries to 0" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: "{}"
      }

      result = Response.new(finch_response, method: :get, url: "https://example.com")

      assert result.elapsed_ms == 0
      assert result.retries == 0
    end

    test "allows custom data via opts" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: ~s({"raw": true})
      }

      result =
        Response.new(finch_response,
          method: :get,
          url: "https://example.com",
          data: %{"custom" => "data"}
        )

      assert result.data == %{"custom" => "data"}
    end
  end

  describe "header/2" do
    test "retrieves header value case-insensitively" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [{"X-Custom-Header", "value"}],
        body: "{}"
      }

      response = Response.new(finch_response, method: :get, url: "https://example.com")

      assert Response.header(response, "x-custom-header") == "value"
      assert Response.header(response, "X-CUSTOM-HEADER") == "value"
    end

    test "returns nil for missing header" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: "{}"
      }

      response = Response.new(finch_response, method: :get, url: "https://example.com")

      assert Response.header(response, "x-missing") == nil
    end
  end

  describe "parse/2" do
    test "returns data when no parser provided" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: ~s({"key": "value"})
      }

      response = Response.new(finch_response, method: :get, url: "https://example.com")

      assert {:ok, %{"key" => "value"}} = Response.parse(response)
    end

    test "applies function parser" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: ~s({"count": 5})
      }

      response = Response.new(finch_response, method: :get, url: "https://example.com")

      assert {:ok, result} = Response.parse(response, fn data -> data["count"] * 2 end)
      assert result == 10
    end

    test "handles parser exceptions" do
      finch_response = %Finch.Response{
        status: 200,
        headers: [],
        body: ~s({"key": "value"})
      }

      response = Response.new(finch_response, method: :get, url: "https://example.com")

      assert {:error, %ArithmeticError{}} = Response.parse(response, fn _ -> 1 / 0 end)
    end
  end
end
