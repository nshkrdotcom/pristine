defmodule Tinkex.HuggingFaceTest do
  use ExUnit.Case, async: true

  alias Tinkex.HuggingFace
  alias Tinkex.Error

  describe "resolve_file/4" do
    @tag :tmp_dir
    test "returns cached file if exists", %{tmp_dir: tmp_dir} do
      # Create a cached file
      repo_id = "test-org/test-model"
      revision = "main"
      filename = "config.json"

      cache_path = Path.join([tmp_dir, "hf", "test-org__test-model", revision, filename])
      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, ~s({"test": true}))

      {:ok, path} = HuggingFace.resolve_file(repo_id, revision, filename, cache_dir: tmp_dir)

      assert path == cache_path
      assert File.exists?(path)
    end

    test "returns error for missing file without network" do
      # Without setting up httpc, this will fail gracefully
      {:error, %Error{}} =
        HuggingFace.resolve_file(
          "nonexistent/model",
          "main",
          "missing.json",
          cache_dir: System.tmp_dir!(),
          http_timeout_ms: 100
        )
    end
  end

  describe "sanitize_repo_id/1" do
    test "replaces slashes with double underscores" do
      assert HuggingFace.sanitize_repo_id("org/model") == "org__model"
    end

    test "replaces double dots with single underscore" do
      assert HuggingFace.sanitize_repo_id("org/model..path") == "org__model_path"
    end

    test "handles complex repo IDs" do
      assert HuggingFace.sanitize_repo_id("org/model/variant") == "org__model__variant"
    end
  end

  describe "default_cache_dir/0" do
    test "returns a cache directory path" do
      cache_dir = HuggingFace.default_cache_dir()
      assert is_binary(cache_dir)
      assert String.contains?(cache_dir, "tinkex")
    end
  end

  describe "build_hf_url/3" do
    test "builds correct HuggingFace URL" do
      url = HuggingFace.build_hf_url("org/model", "main", "config.json")
      assert url == "https://huggingface.co/org/model/resolve/main/config.json"
    end

    test "handles revision with commit hash" do
      url = HuggingFace.build_hf_url("org/model", "abc123def", "tokenizer.json")
      assert url == "https://huggingface.co/org/model/resolve/abc123def/tokenizer.json"
    end
  end
end
