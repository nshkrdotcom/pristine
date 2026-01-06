defmodule Examples.TinkexGenerationTest do
  @moduledoc """
  Tests for generating Tinkex client from manifest.

  Verifies that the code generator produces valid, compilable Elixir
  code with proper structure and documentation.
  """

  use ExUnit.Case

  alias Pristine.Codegen
  alias Pristine.Manifest

  @manifest_path "examples/tinkex/manifest.json"
  @output_path "examples/tinkex/generated"

  setup do
    # Clean output directory
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)

    on_exit(fn ->
      # Optionally clean up after tests
      # File.rm_rf!(@output_path)
      :ok
    end)

    :ok
  end

  describe "tinkex generation" do
    test "generates all expected files" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      assert :ok = Codegen.write_sources(sources)

      # Check main files exist
      assert File.exists?(Path.join(@output_path, "client.ex"))

      # Check resource files exist
      assert File.exists?(Path.join(@output_path, "resources/models.ex"))
      assert File.exists?(Path.join(@output_path, "resources/sampling.ex"))

      # Check type files exist
      assert File.exists?(Path.join(@output_path, "types/model.ex"))
      assert File.exists?(Path.join(@output_path, "types/model_list.ex"))
      assert File.exists?(Path.join(@output_path, "types/api_sample_request.ex"))
      assert File.exists?(Path.join(@output_path, "types/sample_result.ex"))
    end

    test "generated sources map contains expected entries" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      # Verify sources map has entries
      assert map_size(sources) > 0

      # Check for key files
      paths = Map.keys(sources)
      assert Enum.any?(paths, &String.ends_with?(&1, "client.ex"))
      assert Enum.any?(paths, &String.contains?(&1, "resources"))
      assert Enum.any?(paths, &String.contains?(&1, "types"))
    end

    test "generated client module has correct structure" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      content = File.read!(Path.join(@output_path, "client.ex"))

      assert content =~ "defmodule Tinkex.Client"
      assert content =~ "defstruct"
      assert content =~ "@type t ::"
      assert content =~ "def new("
      assert content =~ "@moduledoc"
    end

    test "generated models resource module has correct functions" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      content = File.read!(Path.join(@output_path, "resources/models.ex"))

      assert content =~ "defmodule Tinkex.Models"
      assert content =~ "list_models"
      assert content =~ "get_model"
      assert content =~ "@doc"
      assert content =~ "@spec"
    end

    test "generated sampling resource module has correct functions" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      content = File.read!(Path.join(@output_path, "resources/sampling.ex"))

      assert content =~ "defmodule Tinkex.Sampling"
      assert content =~ "create_sample"
      assert content =~ "create_sample_stream"
      assert content =~ "get_sample"
      assert content =~ "create_sample_async"
    end

    test "generated type modules have schema functions" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      content = File.read!(Path.join(@output_path, "types/api_sample_request.ex"))

      assert content =~ "defmodule Tinkex.Types.ApiSampleRequest"
      assert content =~ "def schema"
      assert content =~ "Sinter.Schema.define"
    end

    test "generated code includes documentation from manifest" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      models_content = File.read!(Path.join(@output_path, "resources/models.ex"))

      # Check that description from manifest is included
      assert models_content =~ "List all available models"
      assert models_content =~ "Get details for a specific model"
    end

    test "generated client has resource accessors" do
      {:ok, manifest} = Manifest.load_file(@manifest_path)

      {:ok, sources} =
        Codegen.build_sources(manifest,
          output_dir: @output_path,
          namespace: "Tinkex"
        )

      Codegen.write_sources(sources)

      content = File.read!(Path.join(@output_path, "client.ex"))

      # Check for resource accessor functions
      assert content =~ "def models("
      assert content =~ "def sampling("
    end
  end

  describe "mix pristine.generate task" do
    test "generates files with mix task" do
      Mix.Task.run("app.start")

      # Run the generation task
      Mix.Task.run("pristine.generate", [
        "--manifest",
        @manifest_path,
        "--output",
        @output_path,
        "--namespace",
        "Tinkex"
      ])

      # Verify files were created
      assert File.exists?(Path.join(@output_path, "client.ex"))
    end
  end
end
