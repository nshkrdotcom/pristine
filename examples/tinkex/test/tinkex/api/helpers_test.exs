defmodule Tinkex.API.HelpersTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Helpers
  alias Tinkex.Config

  setup do
    System.put_env("TINKER_API_KEY", "tml-test-key")
    on_exit(fn -> System.delete_env("TINKER_API_KEY") end)
    {:ok, config: Config.new()}
  end

  describe "with_raw_response/1" do
    test "adds :wrapped response option to keyword list" do
      opts = [timeout: 5000]
      result = Helpers.with_raw_response(opts)
      assert result[:response] == :wrapped
      assert result[:timeout] == 5000
    end

    test "accepts empty keyword list" do
      result = Helpers.with_raw_response([])
      assert result == [response: :wrapped]
    end

    test "wraps Config struct", %{config: config} do
      result = Helpers.with_raw_response(config)
      assert result[:config] == config
      assert result[:response] == :wrapped
    end

    test "overwrites existing response option" do
      opts = [response: :stream, timeout: 5000]
      result = Helpers.with_raw_response(opts)
      assert result[:response] == :wrapped
    end
  end

  describe "with_streaming_response/1" do
    test "adds :stream response option to keyword list" do
      opts = [timeout: 30_000]
      result = Helpers.with_streaming_response(opts)
      assert result[:response] == :stream
      assert result[:timeout] == 30_000
    end

    test "accepts empty keyword list" do
      result = Helpers.with_streaming_response([])
      assert result == [response: :stream]
    end

    test "wraps Config struct", %{config: config} do
      result = Helpers.with_streaming_response(config)
      assert result[:config] == config
      assert result[:response] == :stream
    end

    test "overwrites existing response option" do
      opts = [response: :wrapped, timeout: 5000]
      result = Helpers.with_streaming_response(opts)
      assert result[:response] == :stream
    end
  end
end
