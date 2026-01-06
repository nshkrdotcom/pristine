defmodule Tinkex.Multipart.EncoderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.Encoder

  describe "encode_multipart/3" do
    test "returns error for non-map form_fields" do
      assert Encoder.encode_multipart("invalid", nil) == {:error, :invalid_form_fields}
      assert Encoder.encode_multipart(123, nil) == {:error, :invalid_form_fields}
      assert Encoder.encode_multipart([1, 2], nil) == {:error, :invalid_form_fields}
    end

    test "encodes empty form fields with no files" do
      assert {:ok, body, content_type} = Encoder.encode_multipart(%{}, nil)
      assert String.starts_with?(content_type, "multipart/form-data; boundary=")
      assert String.contains?(body, "--")
    end

    test "encodes single form field" do
      assert {:ok, body, content_type} = Encoder.encode_multipart(%{"name" => "test"}, nil)
      assert String.contains?(content_type, "multipart/form-data; boundary=")
      assert String.contains?(body, "Content-Disposition: form-data; name=\"name\"")
      assert String.contains?(body, "test")
    end

    test "encodes multiple form fields" do
      fields = %{"name" => "alice", "age" => "30"}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(fields, nil)
      assert String.contains?(body, "name=\"name\"")
      assert String.contains?(body, "alice")
      assert String.contains?(body, "name=\"age\"")
      assert String.contains?(body, "30")
    end

    test "encodes list values as multiple parts with same name" do
      fields = %{"tags" => ["a", "b", "c"]}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(fields, nil)
      # Should have multiple parts with name="tags"
      assert length(String.split(body, "name=\"tags\"")) == 4
    end

    test "uses provided boundary" do
      custom_boundary = "custom-boundary-12345"
      assert {:ok, body, content_type} = Encoder.encode_multipart(%{}, nil, custom_boundary)
      assert content_type == "multipart/form-data; boundary=#{custom_boundary}"
      assert String.contains?(body, "--#{custom_boundary}")
    end

    test "encodes file with map input" do
      files = %{"file" => {"test.txt", "file content"}}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "name=\"file\"")
      assert String.contains?(body, "filename=\"test.txt\"")
      assert String.contains?(body, "file content")
    end

    test "encodes file with list input" do
      files = [{"file", {"test.txt", "file content"}}]
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "name=\"file\"")
      assert String.contains?(body, "filename=\"test.txt\"")
    end

    test "encodes file with content type" do
      files = %{"file" => {"test.json", "{}", "application/json"}}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "Content-Type: application/json")
    end

    test "encodes file with custom headers" do
      files = %{"file" => {"test.txt", "content", "text/plain", %{"X-Custom" => "value"}}}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "X-Custom: value")
    end

    test "encodes raw content without filename" do
      files = %{"data" => "raw binary content"}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "name=\"data\"")
      assert String.contains?(body, "raw binary content")
      # No filename should be present
      refute String.contains?(body, "filename=")
    end

    test "uses default content type for files" do
      files = %{"file" => {"test.bin", "content"}}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{}, files)
      assert String.contains?(body, "Content-Type: application/octet-stream")
    end

    test "returns error for invalid files format" do
      assert {:error, {:invalid_files, :not_valid}} = Encoder.encode_multipart(%{}, :not_valid)
    end

    test "combines form fields and files" do
      fields = %{"name" => "upload"}
      files = %{"file" => {"doc.pdf", "pdf content", "application/pdf"}}
      assert {:ok, body, _content_type} = Encoder.encode_multipart(fields, files)
      assert String.contains?(body, "name=\"name\"")
      assert String.contains?(body, "upload")
      assert String.contains?(body, "name=\"file\"")
      assert String.contains?(body, "filename=\"doc.pdf\"")
      assert String.contains?(body, "pdf content")
    end

    test "body ends with closing boundary" do
      boundary = "test-boundary"
      assert {:ok, body, _content_type} = Encoder.encode_multipart(%{"a" => "b"}, nil, boundary)
      assert String.ends_with?(body, "--#{boundary}--\r\n")
    end
  end

  describe "generate_boundary/0" do
    test "generates 32 character hex string" do
      boundary = Encoder.generate_boundary()
      assert String.length(boundary) == 32
      assert Regex.match?(~r/^[a-f0-9]+$/, boundary)
    end

    test "generates unique boundaries" do
      boundaries = for _ <- 1..100, do: Encoder.generate_boundary()
      assert length(Enum.uniq(boundaries)) == 100
    end
  end
end
