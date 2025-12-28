defmodule Mix.Tasks.Pristine.DocsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pristine.Docs

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  describe "run/1" do
    test "generates documentation to stdout", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)

      output =
        capture_io(fn ->
          Docs.run(["--manifest", manifest_path])
        end)

      assert output =~ "# TestAPI"
      assert output =~ "## Overview"
    end

    test "writes to file with --output option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "api.md")

      capture_io(fn ->
        Docs.run([
          "--manifest",
          manifest_path,
          "--output",
          output_path
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert content =~ "# TestAPI"
    end

    test "generates HTML with --format html option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "api.html")

      capture_io(fn ->
        Docs.run([
          "--manifest",
          manifest_path,
          "--output",
          output_path,
          "--format",
          "html"
        ])
      end)

      content = File.read!(output_path)
      assert content =~ "<html>"
      assert content =~ "<h1>TestAPI</h1>"
    end

    test "includes examples with --examples flag", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)

      output =
        capture_io(fn ->
          Docs.run(["--manifest", manifest_path, "--examples"])
        end)

      assert output =~ "Example"
    end

    test "exits with error for missing manifest file", %{tmp_dir: tmp_dir} do
      invalid_path = Path.join(tmp_dir, "nonexistent.json")

      assert_raise Mix.Error, ~r/not found/, fn ->
        Docs.run(["--manifest", invalid_path])
      end
    end

    test "requires --manifest option" do
      assert_raise Mix.Error, ~r/--manifest.*required/, fn ->
        Docs.run([])
      end
    end
  end

  defp create_test_manifest(dir) do
    path = Path.join(dir, "manifest.json")

    manifest = %{
      "name" => "TestAPI",
      "version" => "1.0.0",
      "endpoints" => [
        %{
          "id" => "get_user",
          "method" => "GET",
          "path" => "/users/{id}",
          "response" => "User"
        }
      ],
      "types" => %{
        "User" => %{
          "fields" => %{
            "id" => %{"type" => "string", "required" => true},
            "name" => %{"type" => "string", "required" => true}
          }
        }
      }
    }

    File.write!(path, Jason.encode!(manifest))
    path
  end
end
