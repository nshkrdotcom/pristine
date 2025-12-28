defmodule Mix.Tasks.Pristine.OpenapiTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pristine.Openapi

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  describe "run/1" do
    test "generates OpenAPI spec to stdout", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)

      output =
        capture_io(fn ->
          Openapi.run(["--manifest", manifest_path])
        end)

      assert output =~ "openapi"
      assert {:ok, _} = Jason.decode(output)
    end

    test "writes to file with --output option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "openapi.json")

      capture_io(fn ->
        Openapi.run([
          "--manifest",
          manifest_path,
          "--output",
          output_path
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert {:ok, spec} = Jason.decode(content)
      assert spec["openapi"] == "3.1.0"
    end

    test "generates YAML with --format yaml option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "openapi.yaml")

      capture_io(fn ->
        Openapi.run([
          "--manifest",
          manifest_path,
          "--output",
          output_path,
          "--format",
          "yaml"
        ])
      end)

      content = File.read!(output_path)
      assert content =~ "openapi:"
    end

    test "exits with error for missing manifest file", %{tmp_dir: tmp_dir} do
      invalid_path = Path.join(tmp_dir, "nonexistent.json")

      assert_raise Mix.Error, ~r/not found/, fn ->
        Openapi.run(["--manifest", invalid_path])
      end
    end

    test "exits with error for invalid manifest", %{tmp_dir: tmp_dir} do
      invalid_path = Path.join(tmp_dir, "invalid.json")
      File.write!(invalid_path, "not valid json")

      assert_raise Mix.Error, ~r/Failed to load manifest/, fn ->
        Openapi.run(["--manifest", invalid_path])
      end
    end

    test "requires --manifest option" do
      assert_raise Mix.Error, ~r/--manifest.*required/, fn ->
        Openapi.run([])
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
          "id" => "test",
          "method" => "GET",
          "path" => "/test"
        }
      ],
      "types" => %{
        "TestType" => %{
          "fields" => %{
            "name" => %{"type" => "string", "required" => true}
          }
        }
      }
    }

    File.write!(path, Jason.encode!(manifest))
    path
  end
end
