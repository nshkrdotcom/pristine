defmodule Tinkex.Files.TransformTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Transform

  describe "transform_file/1" do
    test "transforms binary content" do
      assert {:ok, "hello"} = Transform.transform_file("hello")
    end

    test "transforms 2-tuple" do
      assert {:ok, {"file.txt", "content"}} = Transform.transform_file({"file.txt", "content"})
    end

    test "transforms 3-tuple" do
      assert {:ok, {"file.txt", "content", "text/plain"}} =
               Transform.transform_file({"file.txt", "content", "text/plain"})
    end

    test "transforms 4-tuple with headers" do
      assert {:ok, {"file.txt", "content", "text/plain", %{"x-custom" => "value"}}} =
               Transform.transform_file(
                 {"file.txt", "content", "text/plain", %{"x-custom" => "value"}}
               )
    end

    test "returns error for invalid input" do
      assert {:error, {:invalid_file_type, _}} = Transform.transform_file(123)
    end
  end

  describe "transform_files/1" do
    test "returns nil for nil input" do
      assert {:ok, nil} = Transform.transform_files(nil)
    end

    test "transforms map of files" do
      files = %{
        "file1" => "content1",
        "file2" => {"name.txt", "content2"}
      }

      assert {:ok, transformed} = Transform.transform_files(files)
      assert transformed["file1"] == "content1"
      assert transformed["file2"] == {"name.txt", "content2"}
    end

    test "transforms list of files" do
      files = [
        {"file1", "content1"},
        {"file2", {"name.txt", "content2"}}
      ]

      assert {:ok, transformed} = Transform.transform_files(files)
      assert [{"file1", "content1"}, {"file2", {"name.txt", "content2"}}] = transformed
    end

    test "returns error for invalid files" do
      assert {:error, _} = Transform.transform_files(%{"bad" => 123})
    end

    test "returns error for invalid list format" do
      assert {:error, {:invalid_request_files, _}} = Transform.transform_files([1, 2, 3])
    end
  end

  describe "transform_files_async/1" do
    test "returns a task" do
      task = Transform.transform_files_async(%{"file" => "content"})
      assert %Task{} = task
      assert {:ok, %{"file" => "content"}} = Task.await(task)
    end
  end
end
