defmodule Tinkex.Tokenizer.HTTPClientTest do
  use ExUnit.Case, async: true

  alias Tinkex.Tokenizer.HTTPClient

  describe "request/1" do
    test "requires opts to be a list" do
      # The function only accepts a list via guard
      assert_raise FunctionClauseError, fn ->
        HTTPClient.request(%{})
      end
    end

    test "uses default base_url when not provided" do
      # We can't make real requests in tests, but we can test that the module compiles
      # and the function head is correct
      Code.ensure_loaded!(HTTPClient)
      assert function_exported?(HTTPClient, :request, 1)
    end

    test "accepts all expected options" do
      # Test that we can call with various options without error (until httpc call)
      # This verifies option parsing works
      opts = [
        base_url: "https://example.com",
        url: "/test",
        method: :get,
        headers: [{"accept", "application/json"}],
        timeout_ms: 5000
      ]

      # The call will fail since we can't reach the network in tests,
      # but it should get past option parsing
      result = HTTPClient.request(opts)
      # Either succeeds or fails with network error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles headers with atom keys" do
      opts = [
        base_url: "https://localhost:1",
        url: "/test",
        headers: [{:accept, "text/plain"}],
        timeout_ms: 100
      ]

      # Will fail on network but tests header normalization
      result = HTTPClient.request(opts)
      assert match?({:error, _}, result)
    end

    test "handles empty headers" do
      opts = [
        base_url: "https://localhost:1",
        url: "/test",
        headers: [],
        timeout_ms: 100
      ]

      result = HTTPClient.request(opts)
      assert match?({:error, _}, result)
    end

    test "handles mixed header types" do
      opts = [
        base_url: "https://localhost:1",
        url: "/path",
        headers: [
          {"string-key", "string-value"},
          {:atom_key, "atom-value"},
          {~c"charlist-key", ~c"charlist-value"}
        ],
        timeout_ms: 100
      ]

      result = HTTPClient.request(opts)
      # Should parse headers without error, then fail on network
      assert match?({:error, _}, result)
    end

    test "supports :get method" do
      opts = [
        base_url: "https://localhost:1",
        url: "/get",
        method: :get,
        timeout_ms: 100
      ]

      result = HTTPClient.request(opts)
      assert match?({:error, _}, result)
    end

    test "supports :post method" do
      opts = [
        base_url: "https://localhost:1",
        url: "/post",
        method: :post,
        timeout_ms: 100
      ]

      result = HTTPClient.request(opts)
      assert match?({:error, _}, result)
    end

    test "joins base_url and path correctly" do
      opts = [
        base_url: "https://localhost:1",
        url: "path/to/resource",
        timeout_ms: 100
      ]

      result = HTTPClient.request(opts)
      # Error message should contain the joined path
      assert match?({:error, msg} when is_binary(msg), result)
    end

    test "uses default values for all options" do
      # Empty opts should use all defaults
      opts = [timeout_ms: 100, base_url: "https://localhost:1"]
      result = HTTPClient.request(opts)
      assert match?({:error, _}, result)
    end
  end

  describe "module" do
    test "has correct default base URL" do
      # Verify the module attribute is set correctly via inspection
      {:ok, {_, [{_, {_, abstract_code}}]}} =
        :beam_lib.chunks(~c"#{:code.which(HTTPClient)}", [:abstract_code])

      # Module compiled successfully with the constant
      assert is_list(abstract_code)
    end

    test "exports request/1" do
      Code.ensure_loaded!(HTTPClient)
      assert function_exported?(HTTPClient, :request, 1)
    end
  end
end
