defmodule Tinkex.EnvTest do
  use ExUnit.Case, async: true

  alias Tinkex.Env

  describe "snapshot/1" do
    test "normalizes values" do
      env = %{
        "TINKER_API_KEY" => " api ",
        "TINKER_BASE_URL" => "https://example.com/ ",
        "TINKER_TAGS" => "tag1, tag2, ,tag3",
        "TINKER_FEATURE_GATES" => "async_sampling,other",
        "TINKER_TELEMETRY" => "0",
        "TINKER_LOG" => "Warning",
        "CLOUDFLARE_ACCESS_CLIENT_ID" => "cf-id",
        "CLOUDFLARE_ACCESS_CLIENT_SECRET" => "cf-secret",
        "TINKEX_DUMP_HEADERS" => "1",
        "TINKEX_POLL_BACKOFF" => "exponential",
        "TINKEX_DEFAULT_HEADERS" => ~s({"Authorization":"Bearer token","x-extra":"1"}),
        "TINKEX_DEFAULT_QUERY" => ~s({"mode":"fast","flag":true}),
        "TINKEX_HTTP_POOL" => "custom_pool"
      }

      snapshot = Env.snapshot(env)

      assert snapshot.api_key == "api"
      assert snapshot.base_url == "https://example.com/"
      assert snapshot.tags == ["tag1", "tag2", "tag3"]
      assert snapshot.feature_gates == ["async_sampling", "other"]
      refute snapshot.telemetry_enabled?
      assert snapshot.log_level == :warn
      assert snapshot.cf_access_client_id == "cf-id"
      assert snapshot.cf_access_client_secret == "cf-secret"
      assert snapshot.dump_headers?
      assert snapshot.poll_backoff == :exponential
      assert snapshot.default_headers == %{"Authorization" => "Bearer token", "x-extra" => "1"}
      assert snapshot.default_query == %{"flag" => "true", "mode" => "fast"}
      assert snapshot.http_pool == :custom_pool
    end

    test "defaults feature_gates to async_sampling when unset" do
      snapshot = Env.snapshot(%{})
      assert snapshot.feature_gates == ["async_sampling"]
    end
  end

  describe "defaults and blank values" do
    test "handles blank and missing values" do
      env = %{
        "TINKER_API_KEY" => " ",
        "TINKER_TELEMETRY" => "maybe",
        "TINKEX_DUMP_HEADERS" => "",
        "TINKER_FEATURE_GATES" => " ",
        "TINKEX_POLL_BACKOFF" => "0"
      }

      assert Env.api_key(env) == nil
      assert Env.base_url(env) == nil
      assert Env.tags(env) == []
      assert Env.feature_gates(env) == ["async_sampling"]
      assert Env.telemetry_enabled?(env)
      refute Env.dump_headers?(env)
      assert Env.poll_backoff(env) == nil
    end
  end

  describe "boolean parsing" do
    test "accepts common truthy values" do
      true_env = %{"TINKER_TELEMETRY" => "YES", "TINKEX_DUMP_HEADERS" => "on"}

      assert Env.telemetry_enabled?(true_env)
      assert Env.dump_headers?(true_env)
    end

    test "accepts common falsey values" do
      false_env = %{"TINKER_TELEMETRY" => "false", "TINKEX_DUMP_HEADERS" => "0"}

      refute Env.telemetry_enabled?(false_env)
      refute Env.dump_headers?(false_env)
    end

    test "defaults telemetry to true" do
      assert Env.telemetry_enabled?(%{})
    end

    test "defaults dump_headers to false" do
      refute Env.dump_headers?(%{})
    end
  end

  describe "log_level/1" do
    test "parses debug level" do
      assert Env.log_level(%{"TINKER_LOG" => "DEBUG"}) == :debug
      assert Env.log_level(%{"TINKER_LOG" => "debug"}) == :debug
    end

    test "parses warn level" do
      assert Env.log_level(%{"TINKER_LOG" => "warn"}) == :warn
      assert Env.log_level(%{"TINKER_LOG" => "warning"}) == :warn
    end

    test "parses error level" do
      assert Env.log_level(%{"TINKER_LOG" => "error"}) == :error
    end

    test "parses info level" do
      assert Env.log_level(%{"TINKER_LOG" => "info"}) == :info
    end

    test "returns nil for unknown values" do
      assert Env.log_level(%{"TINKER_LOG" => "unknown"}) == nil
    end

    test "returns nil when not set" do
      assert Env.log_level(%{}) == nil
    end
  end

  describe "parity_mode/1" do
    test "returns :python for TINKEX_PARITY=python" do
      assert Env.parity_mode(%{"TINKEX_PARITY" => "python"}) == :python
      assert Env.parity_mode(%{"TINKEX_PARITY" => "Python"}) == :python
      assert Env.parity_mode(%{"TINKEX_PARITY" => "PYTHON"}) == :python
    end

    test "returns :beam for TINKEX_PARITY=beam" do
      assert Env.parity_mode(%{"TINKEX_PARITY" => "beam"}) == :beam
      assert Env.parity_mode(%{"TINKEX_PARITY" => "BEAM"}) == :beam
      assert Env.parity_mode(%{"TINKEX_PARITY" => "elixir"}) == :beam
      assert Env.parity_mode(%{"TINKEX_PARITY" => "ELIXIR"}) == :beam
    end

    test "returns nil for missing or empty value" do
      assert Env.parity_mode(%{}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => ""}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => " "}) == nil
    end

    test "returns nil for unknown values" do
      assert Env.parity_mode(%{"TINKEX_PARITY" => "java"}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => "rust"}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => "1"}) == nil
    end

    test "is included in snapshot" do
      env = %{"TINKEX_PARITY" => "python"}
      snapshot = Env.snapshot(env)
      assert snapshot.parity_mode == :python
    end
  end

  describe "poll_backoff/1" do
    test "returns :exponential for truthy values" do
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "1"}) == :exponential
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "true"}) == :exponential
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "exponential"}) == :exponential
    end

    test "returns nil for falsey values" do
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "0"}) == nil
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "false"}) == nil
      assert Env.poll_backoff(%{"TINKEX_POLL_BACKOFF" => "none"}) == nil
    end

    test "returns nil when not set" do
      assert Env.poll_backoff(%{}) == nil
    end
  end

  describe "pool configuration" do
    test "pool_size parses positive integers" do
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "100"}) == 100
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "1"}) == 1
    end

    test "pool_size returns nil for invalid values" do
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "0"}) == nil
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "-1"}) == nil
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "abc"}) == nil
      assert Env.pool_size(%{}) == nil
    end

    test "pool_count parses positive integers" do
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "4"}) == 4
    end

    test "pool_count returns nil for invalid values" do
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "0"}) == nil
      assert Env.pool_count(%{}) == nil
    end
  end

  describe "proxy configuration" do
    test "proxy returns URL string" do
      assert Env.proxy(%{"TINKEX_PROXY" => "http://proxy.example.com:8080"}) ==
               "http://proxy.example.com:8080"
    end

    test "proxy returns nil when not set" do
      assert Env.proxy(%{}) == nil
    end

    test "proxy_headers parses JSON array" do
      json = ~s([["proxy-authorization", "Basic abc123"], ["x-custom", "value"]])
      headers = Env.proxy_headers(%{"TINKEX_PROXY_HEADERS" => json})
      assert headers == [{"proxy-authorization", "Basic abc123"}, {"x-custom", "value"}]
    end

    test "proxy_headers returns empty list for invalid JSON" do
      assert Env.proxy_headers(%{"TINKEX_PROXY_HEADERS" => "invalid"}) == []
      assert Env.proxy_headers(%{}) == []
    end
  end

  describe "default headers and query" do
    test "default_headers parses JSON object" do
      json = ~s({"Authorization": "Bearer token", "X-Custom": "value"})
      headers = Env.default_headers(%{"TINKEX_DEFAULT_HEADERS" => json})
      assert headers == %{"Authorization" => "Bearer token", "X-Custom" => "value"}
    end

    test "default_headers returns empty map for invalid JSON" do
      assert Env.default_headers(%{"TINKEX_DEFAULT_HEADERS" => "invalid"}) == %{}
      assert Env.default_headers(%{}) == %{}
    end

    test "default_query parses JSON object" do
      json = ~s({"mode": "fast", "count": 10})
      query = Env.default_query(%{"TINKEX_DEFAULT_QUERY" => json})
      assert query == %{"mode" => "fast", "count" => "10"}
    end

    test "default_query returns empty map for invalid JSON" do
      assert Env.default_query(%{"TINKEX_DEFAULT_QUERY" => "invalid"}) == %{}
      assert Env.default_query(%{}) == %{}
    end
  end

  describe "http_pool/1" do
    test "parses atom name" do
      assert Env.http_pool(%{"TINKEX_HTTP_POOL" => "custom_pool"}) == :custom_pool
    end

    test "returns nil when not set" do
      assert Env.http_pool(%{}) == nil
    end

    test "returns nil for empty string" do
      assert Env.http_pool(%{"TINKEX_HTTP_POOL" => ""}) == nil
      assert Env.http_pool(%{"TINKEX_HTTP_POOL" => "  "}) == nil
    end
  end

  describe "otel_propagate/1" do
    test "returns true for truthy values" do
      assert Env.otel_propagate(%{"TINKEX_OTEL_PROPAGATE" => "true"})
      assert Env.otel_propagate(%{"TINKEX_OTEL_PROPAGATE" => "1"})
    end

    test "returns false for falsey values" do
      refute Env.otel_propagate(%{"TINKEX_OTEL_PROPAGATE" => "false"})
      refute Env.otel_propagate(%{"TINKEX_OTEL_PROPAGATE" => "0"})
    end

    test "defaults to false" do
      refute Env.otel_propagate(%{})
    end
  end

  describe "redact/1" do
    test "redacts api_key" do
      snapshot = %{api_key: "tml-abc", tags: ["a"]}
      redacted = Env.redact(snapshot)
      assert redacted.api_key == "[REDACTED]"
      assert redacted.tags == ["a"]
    end

    test "redacts cf_access_client_secret" do
      snapshot = %{cf_access_client_secret: "secret"}
      redacted = Env.redact(snapshot)
      assert redacted.cf_access_client_secret == "[REDACTED]"
    end

    test "redacts sensitive headers in default_headers" do
      snapshot = %{
        default_headers: %{
          "Authorization" => "Bearer token",
          "x-api-key" => "key",
          "x-extra" => "1"
        }
      }

      redacted = Env.redact(snapshot)

      assert redacted.default_headers == %{
               "Authorization" => "[REDACTED]",
               "x-api-key" => "[REDACTED]",
               "x-extra" => "1"
             }
    end

    test "preserves nil values" do
      snapshot = %{api_key: nil, cf_access_client_secret: nil}
      redacted = Env.redact(snapshot)
      assert redacted.api_key == nil
      assert redacted.cf_access_client_secret == nil
    end
  end

  describe "mask_secret/1" do
    test "masks string values" do
      assert Env.mask_secret("secret") == "[REDACTED]"
    end

    test "preserves nil" do
      assert Env.mask_secret(nil) == nil
    end

    test "returns non-strings as-is" do
      assert Env.mask_secret(123) == 123
      assert Env.mask_secret(:atom) == :atom
    end
  end

  describe "tags/1" do
    test "splits comma-separated values" do
      assert Env.tags(%{"TINKER_TAGS" => "a,b,c"}) == ["a", "b", "c"]
    end

    test "trims whitespace" do
      assert Env.tags(%{"TINKER_TAGS" => " a , b , c "}) == ["a", "b", "c"]
    end

    test "filters empty values" do
      assert Env.tags(%{"TINKER_TAGS" => "a,,b,,"}) == ["a", "b"]
    end

    test "returns empty list when not set" do
      assert Env.tags(%{}) == []
    end
  end
end
