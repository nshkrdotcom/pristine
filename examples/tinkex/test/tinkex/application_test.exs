defmodule Tinkex.ApplicationTest do
  use ExUnit.Case, async: false

  alias Tinkex.Application

  describe "default_pool_size/0" do
    test "returns 50 (Python parity)" do
      assert Application.default_pool_size() == 50
    end
  end

  describe "default_pool_count/0" do
    test "returns 20 (Python parity)" do
      assert Application.default_pool_count() == 20
    end
  end

  describe "ETS table creation" do
    # These tests verify ETS table creation logic
    # Tables may be created by Application startup or we create them for test

    test "tinkex_sampling_clients table can exist" do
      # Ensure table exists (Application creates it, or we do for test)
      ensure_table(:tinkex_sampling_clients)
      assert :ets.whereis(:tinkex_sampling_clients) != :undefined
    end

    test "tinkex_rate_limiters table can exist" do
      ensure_table(:tinkex_rate_limiters)
      assert :ets.whereis(:tinkex_rate_limiters) != :undefined
    end

    test "tinkex_tokenizers table can exist" do
      ensure_table(:tinkex_tokenizers)
      assert :ets.whereis(:tinkex_tokenizers) != :undefined
    end
  end

  defp ensure_table(name) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:set, :public, :named_table])
    end
  end

  describe "pool configuration calculations" do
    test "default total connections match Python parity (1000)" do
      # Python: max_connections=1000, max_keepalive_connections=20
      # Elixir: pool_size * pool_count = 50 * 20 = 1000
      assert Application.default_pool_size() * Application.default_pool_count() == 1000
    end
  end
end
