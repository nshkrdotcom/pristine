defmodule Tinkex.Types.LoraConfigTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.LoraConfig

  describe "struct/0" do
    test "has correct default values" do
      config = %LoraConfig{}

      assert config.rank == 32
      assert config.seed == nil
      assert config.train_mlp == true
      assert config.train_attn == true
      assert config.train_unembed == true
    end

    test "accepts custom rank" do
      config = %LoraConfig{rank: 64}
      assert config.rank == 64
    end

    test "accepts seed for reproducibility" do
      config = %LoraConfig{seed: 42}
      assert config.seed == 42
    end

    test "can disable training layers" do
      config = %LoraConfig{train_mlp: false, train_attn: false, train_unembed: false}

      assert config.train_mlp == false
      assert config.train_attn == false
      assert config.train_unembed == false
    end
  end

  describe "JSON encoding" do
    test "encodes all fields correctly" do
      config = %LoraConfig{
        rank: 64,
        seed: 123,
        train_mlp: true,
        train_attn: false,
        train_unembed: true
      }

      json = Jason.encode!(config)
      decoded = Jason.decode!(json)

      assert decoded["rank"] == 64
      assert decoded["seed"] == 123
      assert decoded["train_mlp"] == true
      assert decoded["train_attn"] == false
      assert decoded["train_unembed"] == true
    end

    test "encodes nil seed as null" do
      config = %LoraConfig{}
      json = Jason.encode!(config)
      decoded = Jason.decode!(json)

      assert decoded["seed"] == nil
    end

    test "encodes with all defaults" do
      config = %LoraConfig{}
      json = Jason.encode!(config)
      decoded = Jason.decode!(json)

      assert decoded["rank"] == 32
      assert decoded["train_mlp"] == true
      assert decoded["train_attn"] == true
      assert decoded["train_unembed"] == true
    end
  end
end
