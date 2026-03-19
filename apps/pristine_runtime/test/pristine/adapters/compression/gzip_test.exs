defmodule Pristine.Adapters.Compression.GzipTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Compression.Gzip

  describe "compress/2" do
    test "compresses binary data" do
      data = "Hello, World!"
      assert {:ok, compressed} = Gzip.compress(data)
      assert is_binary(compressed)
      # Compressed data should be different from original
      assert compressed != data
      # Can verify it's valid gzip by decompressing with :zlib
      assert :zlib.gunzip(compressed) == data
    end

    test "compresses empty binary" do
      assert {:ok, compressed} = Gzip.compress("")
      assert is_binary(compressed)
      assert :zlib.gunzip(compressed) == ""
    end

    test "compresses large binary data" do
      # Create a large repetitive string that compresses well
      data = String.duplicate("abcdefghij", 10_000)
      assert {:ok, compressed} = Gzip.compress(data)
      # Compressed should be significantly smaller
      assert byte_size(compressed) < byte_size(data)
      assert :zlib.gunzip(compressed) == data
    end

    test "handles binary with special characters" do
      data = <<0, 1, 2, 255, 254, 253>>
      assert {:ok, compressed} = Gzip.compress(data)
      assert :zlib.gunzip(compressed) == data
    end

    test "accepts options (for future extensibility)" do
      data = "test data"
      assert {:ok, _compressed} = Gzip.compress(data, level: 9)
    end
  end

  describe "decompress/2" do
    test "decompresses gzip data" do
      original = "Hello, World!"
      compressed = :zlib.gzip(original)
      assert {:ok, decompressed} = Gzip.decompress(compressed)
      assert decompressed == original
    end

    test "decompresses empty gzip data" do
      compressed = :zlib.gzip("")
      assert {:ok, decompressed} = Gzip.decompress(compressed)
      assert decompressed == ""
    end

    test "returns error for invalid gzip data" do
      invalid_data = "not gzip data"
      assert {:error, _reason} = Gzip.decompress(invalid_data)
    end

    test "returns error for truncated gzip data" do
      original = "Hello, World!"
      compressed = :zlib.gzip(original)
      # Truncate the data
      truncated = binary_part(compressed, 0, byte_size(compressed) - 5)
      assert {:error, _reason} = Gzip.decompress(truncated)
    end

    test "decompresses large data" do
      original = String.duplicate("test data ", 10_000)
      compressed = :zlib.gzip(original)
      assert {:ok, decompressed} = Gzip.decompress(compressed)
      assert decompressed == original
    end

    test "accepts options (for future extensibility)" do
      compressed = :zlib.gzip("test")
      assert {:ok, _decompressed} = Gzip.decompress(compressed, [])
    end
  end

  describe "content_encoding/0" do
    test "returns gzip content encoding" do
      assert Gzip.content_encoding() == "gzip"
    end
  end

  describe "compress/2 and decompress/2 round trip" do
    test "compresses and decompresses correctly" do
      original = "Round trip test data with unicode: \u{1F600} \u{1F389}"
      assert {:ok, compressed} = Gzip.compress(original)
      assert {:ok, decompressed} = Gzip.decompress(compressed)
      assert decompressed == original
    end

    test "round trip preserves binary data" do
      original = :crypto.strong_rand_bytes(1000)
      assert {:ok, compressed} = Gzip.compress(original)
      assert {:ok, decompressed} = Gzip.decompress(compressed)
      assert decompressed == original
    end
  end
end
