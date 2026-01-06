defmodule Tinkex.ConfigTest do
  use ExUnit.Case, async: true

  alias Tinkex.Config

  describe "new/0" do
    test "creates config from environment when TINKER_API_KEY is set" do
      System.put_env("TINKER_API_KEY", "tml-test-key-12345")
      on_exit(fn -> System.delete_env("TINKER_API_KEY") end)

      config = Config.new()

      assert config.api_key == "tml-test-key-12345"
      assert config.base_url == Config.default_base_url()
    end

    test "raises when api_key is missing" do
      System.delete_env("TINKER_API_KEY")

      assert_raise ArgumentError, ~r/api_key is required/, fn ->
        Config.new()
      end
    end
  end

  describe "new/1 with options" do
    test "creates config with explicit api_key" do
      config = Config.new(api_key: "tml-explicit-key")

      assert config.api_key == "tml-explicit-key"
    end

    test "creates config with explicit base_url" do
      config =
        Config.new(
          api_key: "tml-test-key",
          base_url: "https://custom.example.com"
        )

      assert config.base_url == "https://custom.example.com"
    end

    test "creates config with timeout" do
      config = Config.new(api_key: "tml-test-key", timeout: 30_000)

      assert config.timeout == 30_000
    end

    test "creates config with max_retries" do
      config = Config.new(api_key: "tml-test-key", max_retries: 5)

      assert config.max_retries == 5
    end

    test "creates config with user_metadata" do
      config =
        Config.new(
          api_key: "tml-test-key",
          user_metadata: %{"project" => "test"}
        )

      assert config.user_metadata == %{"project" => "test"}
    end

    test "creates config with tags" do
      config = Config.new(api_key: "tml-test-key", tags: ["training", "experiment-1"])

      assert config.tags == ["training", "experiment-1"]
    end
  end

  describe "validation" do
    test "raises when api_key doesn't start with tml-" do
      assert_raise ArgumentError, ~r/must start with the 'tml-' prefix/, fn ->
        Config.new(api_key: "invalid-key")
      end
    end

    test "raises when timeout is not positive" do
      assert_raise ArgumentError, ~r/timeout must be a positive integer/, fn ->
        Config.new(api_key: "tml-test-key", timeout: 0)
      end
    end

    test "raises when max_retries is negative" do
      assert_raise ArgumentError, ~r/max_retries must be a non-negative integer/, fn ->
        Config.new(api_key: "tml-test-key", max_retries: -1)
      end
    end
  end

  describe "defaults" do
    test "uses Python SDK parity defaults by default" do
      config = Config.new(api_key: "tml-test-key")

      # Python SDK parity: 60s timeout, 10 retries
      assert config.timeout == 60_000
      assert config.max_retries == 10
    end

    test "uses default base_url" do
      config = Config.new(api_key: "tml-test-key")

      assert config.base_url == Config.default_base_url()
    end

    test "telemetry is enabled by default" do
      config = Config.new(api_key: "tml-test-key")

      assert config.telemetry_enabled? == true
    end

    test "default tags includes tinkex-elixir" do
      config = Config.new(api_key: "tml-test-key")

      assert "tinkex-elixir" in config.tags
    end
  end

  describe "parity_mode" do
    test ":beam mode uses conservative BEAM defaults" do
      config = Config.new(api_key: "tml-test-key", parity_mode: :beam)

      # BEAM conservative: 120s timeout, 2 retries
      assert config.timeout == 120_000
      assert config.max_retries == 2
    end

    test ":python mode uses Python SDK defaults" do
      config = Config.new(api_key: "tml-test-key", parity_mode: :python)

      assert config.timeout == 60_000
      assert config.max_retries == 10
    end

    test "explicit options override parity defaults" do
      config =
        Config.new(
          api_key: "tml-test-key",
          parity_mode: :python,
          timeout: 30_000,
          max_retries: 3
        )

      assert config.timeout == 30_000
      assert config.max_retries == 3
    end
  end

  describe "mask_api_key/1" do
    test "masks long keys showing prefix and suffix" do
      masked = Config.mask_api_key("tml-abcdef1234567890")

      assert String.starts_with?(masked, "tml-ab")
      assert String.ends_with?(masked, "7890")
      assert String.contains?(masked, "...")
    end

    test "fully masks short keys" do
      masked = Config.mask_api_key("tml")

      assert masked == "***"
    end

    test "returns nil for nil input" do
      assert Config.mask_api_key(nil) == nil
    end
  end

  describe "struct fields" do
    test "has all expected fields" do
      config = Config.new(api_key: "tml-test-key")

      assert Map.has_key?(config, :api_key)
      assert Map.has_key?(config, :base_url)
      assert Map.has_key?(config, :timeout)
      assert Map.has_key?(config, :max_retries)
      assert Map.has_key?(config, :user_metadata)
      assert Map.has_key?(config, :tags)
      assert Map.has_key?(config, :telemetry_enabled?)
    end
  end
end
