defmodule Tinkex.API.URLTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.URL

  describe "build_url/4" do
    test "builds simple URL without query params" do
      url = URL.build_url("https://api.example.com", "/v1/test", %{}, %{})
      assert url == "https://api.example.com/v1/test"
    end

    test "adds request query params" do
      url = URL.build_url("https://api.example.com", "/v1/test", %{}, %{"key" => "value"})
      assert url == "https://api.example.com/v1/test?key=value"
    end

    test "merges default and request query params" do
      url =
        URL.build_url("https://api.example.com", "/v1/test", %{"default" => "1"}, %{
          "key" => "value"
        })

      assert String.contains?(url, "default=1")
      assert String.contains?(url, "key=value")
    end

    test "request params override default params" do
      url =
        URL.build_url("https://api.example.com", "/v1/test", %{"key" => "old"}, %{"key" => "new"})

      assert String.contains?(url, "key=new")
      refute String.contains?(url, "key=old")
    end

    test "preserves query params from path" do
      url = URL.build_url("https://api.example.com", "/v1/test?existing=1", %{}, %{"new" => "2"})
      assert String.contains?(url, "existing=1")
      assert String.contains?(url, "new=2")
    end

    test "handles paths with leading slash" do
      url = URL.build_url("https://api.example.com", "/v1/test", %{}, %{})
      assert url == "https://api.example.com/v1/test"
    end

    test "handles paths without leading slash" do
      url = URL.build_url("https://api.example.com", "v1/test", %{}, %{})
      assert url == "https://api.example.com/v1/test"
    end

    test "handles base URL with path" do
      url = URL.build_url("https://api.example.com/api", "/v1/test", %{}, %{})
      assert url == "https://api.example.com/api/v1/test"
    end
  end

  describe "normalize_query_params/1" do
    test "returns empty map for nil" do
      assert URL.normalize_query_params(nil) == %{}
    end

    test "normalizes map with atom keys" do
      result = URL.normalize_query_params(%{key: "value"})
      assert result == %{"key" => "value"}
    end

    test "normalizes map with string keys" do
      result = URL.normalize_query_params(%{"key" => "value"})
      assert result == %{"key" => "value"}
    end

    test "filters out nil values" do
      result = URL.normalize_query_params(%{key: "value", nil_key: nil})
      assert result == %{"key" => "value"}
    end

    test "converts numeric values to strings" do
      result = URL.normalize_query_params(%{count: 123, price: 45.67})
      assert result == %{"count" => "123", "price" => "45.67"}
    end

    test "converts atom values to strings" do
      result = URL.normalize_query_params(%{status: :active})
      assert result == %{"status" => "active"}
    end

    test "normalizes keyword list" do
      result = URL.normalize_query_params(key: "value", other: 123)
      assert result == %{"key" => "value", "other" => "123"}
    end

    test "raises for non-keyword list" do
      assert_raise ArgumentError, fn ->
        URL.normalize_query_params([1, 2, 3])
      end
    end

    test "raises for invalid input type" do
      assert_raise ArgumentError, fn ->
        URL.normalize_query_params("invalid")
      end
    end

    test "raises for empty string keys" do
      assert_raise ArgumentError, fn ->
        URL.normalize_query_params(%{"" => "value"})
      end
    end
  end
end
