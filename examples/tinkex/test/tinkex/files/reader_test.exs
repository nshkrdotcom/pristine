defmodule Tinkex.Files.ReaderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Reader

  describe "read_file_content/1" do
    test "reads binary content directly" do
      assert {:ok, "hello"} = Reader.read_file_content("hello")
    end

    test "reads iolist content" do
      assert {:ok, "helloworld"} = Reader.read_file_content(["hello", "world"])
    end

    test "reads actual file path" do
      # mix.exs should exist in the project
      assert {:ok, content} = Reader.read_file_content("mix.exs")
      assert is_binary(content)
      assert String.contains?(content, "defmodule")
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} = Reader.read_file_content("/non/existent/path/file.txt")
    end

    test "returns error for invalid content" do
      assert {:error, :invalid_file_content} = Reader.read_file_content(123)
    end

    test "returns error for directory" do
      assert {:error, :eisdir} = Reader.read_file_content("lib")
    end
  end

  describe "read_file_content!/1" do
    test "returns content for valid input" do
      assert Reader.read_file_content!("hello") == "hello"
    end

    test "raises for invalid input" do
      assert_raise RuntimeError, ~r/Failed to read/, fn ->
        Reader.read_file_content!(123)
      end
    end
  end

  describe "extract_filename/1" do
    test "extracts filename from 2-tuple" do
      assert Reader.extract_filename({"file.txt", "content"}) == "file.txt"
    end

    test "extracts filename from 3-tuple" do
      assert Reader.extract_filename({"file.txt", "content", "text/plain"}) == "file.txt"
    end

    test "extracts filename from 4-tuple" do
      assert Reader.extract_filename({"file.txt", "content", "text/plain", %{}}) == "file.txt"
    end

    test "returns nil for nil filename" do
      assert Reader.extract_filename({nil, "content"}) == nil
    end

    test "extracts basename from file path" do
      assert Reader.extract_filename("./path/to/file.txt") == "file.txt"
    end

    test "returns nil for non-path binary" do
      assert Reader.extract_filename("just content") == nil
    end

    test "returns nil for non-file types" do
      assert Reader.extract_filename(123) == nil
    end
  end
end
