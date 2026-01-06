defmodule Tinkex.API.HeadersTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Headers
  alias Tinkex.Config

  setup do
    System.put_env("TINKER_API_KEY", "tml-test-key")
    on_exit(fn -> System.delete_env("TINKER_API_KEY") end)
    {:ok, config: Config.new()}
  end

  describe "put/3" do
    test "adds new header" do
      headers = [{"accept", "application/json"}]
      result = Headers.put(headers, "x-custom", "value")

      assert Enum.any?(result, fn {k, v} -> k == "x-custom" and v == "value" end)
    end

    test "replaces existing header case-insensitively" do
      headers = [{"Content-Type", "text/plain"}]
      result = Headers.put(headers, "content-type", "application/json")

      assert length(result) == 1
      assert [{"content-type", "application/json"}] = result
    end
  end

  describe "get_normalized/2" do
    test "retrieves header value lowercase and trimmed" do
      headers = [{"Content-Type", "  APPLICATION/JSON  "}]
      assert Headers.get_normalized(headers, "content-type") == "application/json"
    end

    test "returns nil for missing header" do
      headers = [{"accept", "application/json"}]
      assert Headers.get_normalized(headers, "missing") == nil
    end

    test "is case-insensitive" do
      headers = [{"X-Custom", "value"}]
      assert Headers.get_normalized(headers, "x-custom") == "value"
      assert Headers.get_normalized(headers, "X-CUSTOM") == "value"
    end
  end

  describe "find_value/2" do
    test "retrieves original header value" do
      headers = [{"Content-Type", "Application/JSON"}]
      assert Headers.find_value(headers, "content-type") == "Application/JSON"
    end

    test "returns nil for missing header" do
      headers = []
      assert Headers.find_value(headers, "missing") == nil
    end
  end

  describe "to_map/1" do
    test "converts headers to map with lowercase keys" do
      headers = [
        {"Content-Type", "application/json"},
        {"X-Custom", "value"}
      ]

      result = Headers.to_map(headers)

      assert result == %{
               "content-type" => "application/json",
               "x-custom" => "value"
             }
    end

    test "handles empty headers" do
      assert Headers.to_map([]) == %{}
    end
  end

  describe "dedupe/1" do
    test "keeps last occurrence of duplicate headers" do
      headers = [
        {"Content-Type", "text/plain"},
        {"Accept", "application/json"},
        {"content-type", "application/json"}
      ]

      result = Headers.dedupe(headers)
      content_types = Enum.filter(result, fn {k, _} -> String.downcase(k) == "content-type" end)

      assert length(content_types) == 1
      assert [{"content-type", "application/json"}] = content_types
    end
  end

  describe "redact/1" do
    test "redacts x-api-key header" do
      headers = [{"x-api-key", "tml-secret-key-12345"}]
      result = Headers.redact(headers)

      [{_, redacted}] = result
      refute redacted == "tml-secret-key-12345"
      # Env.mask_secret returns "[REDACTED]" or similar
      assert redacted != "tml-secret-key-12345"
    end

    test "redacts authorization header" do
      headers = [{"Authorization", "Bearer secret-token"}]
      result = Headers.redact(headers)

      [{_, redacted}] = result
      refute redacted == "Bearer secret-token"
    end

    test "preserves non-sensitive headers" do
      headers = [{"content-type", "application/json"}]
      result = Headers.redact(headers)

      assert result == headers
    end
  end

  describe "build/4" do
    test "includes standard headers", %{config: config} do
      headers = Headers.build(:get, config, [], 60_000)

      header_map = Headers.to_map(headers)
      assert header_map["accept"] == "application/json"
      assert header_map["content-type"] == "application/json"
      assert header_map["x-api-key"] == "tml-test-key"
    end

    test "includes stainless headers", %{config: config} do
      headers = Headers.build(:get, config, [], 60_000)

      header_map = Headers.to_map(headers)
      assert header_map["x-stainless-os"]
      assert header_map["x-stainless-arch"]
      assert header_map["x-stainless-runtime"] == "BEAM"
    end

    test "adds idempotency key for non-GET methods", %{config: config} do
      headers = Headers.build(:post, config, [], 60_000)

      header_map = Headers.to_map(headers)
      assert header_map["x-idempotency-key"]
    end

    test "skips idempotency key for GET", %{config: config} do
      headers = Headers.build(:get, config, [], 60_000)

      header_map = Headers.to_map(headers)
      refute Map.has_key?(header_map, "x-idempotency-key")
    end

    test "allows custom idempotency key", %{config: config} do
      headers = Headers.build(:post, config, [idempotency_key: "custom-key"], 60_000)

      header_map = Headers.to_map(headers)
      assert header_map["x-idempotency-key"] == "custom-key"
    end

    test "omits idempotency key when specified", %{config: config} do
      headers = Headers.build(:post, config, [idempotency_key: :omit], 60_000)

      header_map = Headers.to_map(headers)
      refute Map.has_key?(header_map, "x-idempotency-key")
    end
  end
end
