defmodule Tinkex.API.CompressionTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.Compression

  describe "decompress/1" do
    test "decompresses gzip-encoded response" do
      compressed_body = :zlib.gzip("test content")

      response = %Finch.Response{
        status: 200,
        body: compressed_body,
        headers: [{"content-encoding", "gzip"}]
      }

      result = Compression.decompress(response)
      assert result.body == "test content"
    end

    test "removes content-encoding header after decompression" do
      compressed_body = :zlib.gzip("test")

      response = %Finch.Response{
        status: 200,
        body: compressed_body,
        headers: [{"content-encoding", "gzip"}, {"content-type", "application/json"}]
      }

      result = Compression.decompress(response)
      refute Enum.any?(result.headers, fn {k, _} -> String.downcase(k) == "content-encoding" end)
      assert Enum.any?(result.headers, fn {k, _} -> String.downcase(k) == "content-type" end)
    end

    test "handles case-insensitive content-encoding header" do
      compressed_body = :zlib.gzip("test")

      response = %Finch.Response{
        status: 200,
        body: compressed_body,
        headers: [{"Content-Encoding", "GZIP"}]
      }

      result = Compression.decompress(response)
      assert result.body == "test"
    end

    test "returns response unchanged for non-gzip encoding" do
      response = %Finch.Response{
        status: 200,
        body: "plain text",
        headers: [{"content-encoding", "identity"}]
      }

      result = Compression.decompress(response)
      assert result.body == "plain text"
      assert result.headers == response.headers
    end

    test "returns response unchanged when no content-encoding header" do
      response = %Finch.Response{
        status: 200,
        body: "plain text",
        headers: []
      }

      result = Compression.decompress(response)
      assert result == response
    end

    test "handles invalid gzip data gracefully" do
      response = %Finch.Response{
        status: 200,
        body: "not actually gzipped",
        headers: [{"content-encoding", "gzip"}]
      }

      result = Compression.decompress(response)
      # Should return original body when decompression fails
      assert result.body == "not actually gzipped"
    end

    test "preserves status code" do
      compressed_body = :zlib.gzip("test")

      response = %Finch.Response{
        status: 201,
        body: compressed_body,
        headers: [{"content-encoding", "gzip"}]
      }

      result = Compression.decompress(response)
      assert result.status == 201
    end
  end
end
