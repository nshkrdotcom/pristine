defmodule Tinkex.Files.TypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Types

  describe "file_content?/1" do
    test "returns true for binary" do
      assert Types.file_content?("hello")
    end

    test "returns true for File.Stream" do
      # Create a mock File.Stream struct
      stream = File.stream!("mix.exs")
      assert Types.file_content?(stream)
    end

    test "returns true for iolist" do
      assert Types.file_content?(["hello", "world"])
      assert Types.file_content?([?h, ?e, ?l, ?l, ?o])
    end

    test "returns false for non-file types" do
      refute Types.file_content?(123)
      refute Types.file_content?(%{})
      refute Types.file_content?(:atom)
    end
  end

  describe "file_types?/1" do
    test "returns true for binary content" do
      assert Types.file_types?("content")
    end

    test "returns true for 2-tuple with filename and content" do
      assert Types.file_types?({"file.txt", "content"})
      assert Types.file_types?({nil, "content"})
    end

    test "returns true for 3-tuple with content type" do
      assert Types.file_types?({"file.txt", "content", "text/plain"})
      assert Types.file_types?({"file.txt", "content", nil})
    end

    test "returns true for 4-tuple with headers" do
      assert Types.file_types?({"file.txt", "content", "text/plain", %{}})
      assert Types.file_types?({"file.txt", "content", nil, []})
    end

    test "returns false for invalid tuples" do
      refute Types.file_types?({123, "content"})
      refute Types.file_types?({"file.txt", 123})
    end

    test "returns false for non-file types" do
      refute Types.file_types?(%{})
      # Note: [1, 2, 3] is a valid iolist, so it's valid file content
      refute Types.file_types?(:atom_value)
    end
  end
end
