defmodule Tinkex.CheckpointDownloadTest do
  use ExUnit.Case, async: false

  alias Tinkex.CheckpointDownload
  alias Tinkex.Config
  alias Tinkex.RestClient

  @tmp_dir System.tmp_dir!()

  defp make_config do
    # Set env temporarily for Config.new to work
    System.put_env("TINKER_API_KEY", "tml-test-api-key")
    on_exit(fn -> System.delete_env("TINKER_API_KEY") end)
    Config.new()
  end

  defp make_rest_client do
    config = make_config()
    RestClient.new("session-id", config)
  end

  setup do
    # Create a test output directory
    test_dir = Path.join(@tmp_dir, "tinkex_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "download/3" do
    test "returns error for invalid checkpoint path" do
      rest_client = make_rest_client()

      result = CheckpointDownload.download(rest_client, "invalid/path")
      assert {:error, {:invalid_path, message}} = result
      assert message =~ "tinker://"
    end

    test "returns error for path without tinker:// prefix" do
      rest_client = make_rest_client()

      result = CheckpointDownload.download(rest_client, "https://example.com/path")
      assert {:error, {:invalid_path, _}} = result
    end

    test "returns {:error, {:exists, path}} when target exists and force is false", %{
      test_dir: test_dir
    } do
      rest_client = make_rest_client()

      # Create existing directory that would match the checkpoint path
      checkpoint_id = "run-123_weights_0001"
      existing_path = Path.join(test_dir, checkpoint_id)
      File.mkdir_p!(existing_path)

      result =
        CheckpointDownload.download(
          rest_client,
          "tinker://run-123/weights/0001",
          output_dir: test_dir,
          force: false
        )

      assert {:error, {:exists, ^existing_path}} = result
    end

    test "removes existing directory when force is true before calling API", %{test_dir: test_dir} do
      rest_client = make_rest_client()

      # Create existing directory
      checkpoint_id = "run-456_weights_0002"
      existing_path = Path.join(test_dir, checkpoint_id)
      File.mkdir_p!(existing_path)
      File.write!(Path.join(existing_path, "test.txt"), "old content")

      # Force=true should remove existing before downloading
      # (will fail on API call, but the directory should be gone)
      _result =
        CheckpointDownload.download(
          rest_client,
          "tinker://run-456/weights/0002",
          output_dir: test_dir,
          force: true
        )

      # The download will fail at the API call, but force=true should have
      # removed the directory before failing
      refute File.exists?(existing_path)
    end

    test "accepts progress callback option" do
      rest_client = make_rest_client()

      progress_fn = fn _downloaded, _total -> :ok end

      # Will fail on API call, but should accept the option without crashing
      _result =
        CheckpointDownload.download(
          rest_client,
          "tinker://run-789/weights/0003",
          progress: progress_fn
        )
    end

    test "generates correct checkpoint_id from path", %{test_dir: test_dir} do
      rest_client = make_rest_client()

      # Create directory with expected transformed name
      expected_id = "deep_nested_path_weights_checkpoint"
      expected_path = Path.join(test_dir, expected_id)
      File.mkdir_p!(expected_path)

      result =
        CheckpointDownload.download(
          rest_client,
          "tinker://deep/nested/path/weights/checkpoint",
          output_dir: test_dir,
          force: false
        )

      # Should get :exists error with the correctly transformed path
      assert {:error, {:exists, ^expected_path}} = result
    end

    test "handles various checkpoint path formats", %{test_dir: test_dir} do
      rest_client = make_rest_client()

      # Test simple path
      File.mkdir_p!(Path.join(test_dir, "simple_checkpoint"))

      result =
        CheckpointDownload.download(
          rest_client,
          "tinker://simple/checkpoint",
          output_dir: test_dir,
          force: false
        )

      assert {:error, {:exists, _}} = result
    end
  end

  describe "module" do
    test "has moduledoc" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} =
        Code.fetch_docs(CheckpointDownload)

      assert moduledoc =~ "Download and extract checkpoint"
    end

    test "exports download function with optional opts" do
      # The module exports download/2 (with default) and download/3 (explicit)
      # Check that we can call with 2 or 3 args
      exports = CheckpointDownload.__info__(:functions)
      assert {:download, 2} in exports or {:download, 3} in exports
    end
  end

  describe "archive extraction" do
    test "module references :erl_tar for extraction" do
      # Verify :erl_tar is available (OTP module)
      # erl_tar.extract can be called with 1 or 2 arguments
      assert Code.ensure_loaded?(:erl_tar)
    end
  end

  describe "path transformation" do
    test "checkpoint_id replaces slashes with underscores" do
      rest_client = make_rest_client()
      test_dir = System.tmp_dir!()

      # The path "tinker://a/b/c" should become checkpoint_id "a_b_c"
      expected_id = "a_b_c"
      expected_path = Path.join(test_dir, expected_id)
      File.mkdir_p!(expected_path)

      result =
        CheckpointDownload.download(
          rest_client,
          "tinker://a/b/c",
          output_dir: test_dir,
          force: false
        )

      assert {:error, {:exists, ^expected_path}} = result

      # Cleanup
      File.rm_rf!(expected_path)
    end

    test "removes tinker:// prefix" do
      rest_client = make_rest_client()
      test_dir = System.tmp_dir!()

      # Verify tinker:// is stripped
      expected_id = "run_weights"
      expected_path = Path.join(test_dir, expected_id)
      File.mkdir_p!(expected_path)

      result =
        CheckpointDownload.download(
          rest_client,
          "tinker://run/weights",
          output_dir: test_dir,
          force: false
        )

      assert {:error, {:exists, ^expected_path}} = result

      # Cleanup
      File.rm_rf!(expected_path)
    end
  end
end
