defmodule Tinkex.RestClientAliasesTest do
  @moduledoc """
  Tests for RestClient convenience aliases for Python SDK parity.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Config
  alias Tinkex.RestClient

  # Mock REST API for testing
  defmodule MockRestAPI do
    def delete_checkpoint(_config, tinker_path) when is_binary(tinker_path) do
      {:ok, %{"deleted" => true, "path" => tinker_path}}
    end

    def publish_checkpoint(_config, tinker_path) do
      {:ok, %{"published" => true, "path" => tinker_path}}
    end

    def unpublish_checkpoint(_config, tinker_path) do
      {:ok, %{"unpublished" => true, "path" => tinker_path}}
    end

    def get_checkpoint_archive_url(_config, tinker_path) when is_binary(tinker_path) do
      {:ok, %{"url" => "https://example.com/archive/#{tinker_path}"}}
    end
  end

  setup do
    config = Config.new(api_key: "tml-test-key", base_url: "https://api.test.com")
    client = RestClient.new("test-session", config, rest_api: MockRestAPI)
    {:ok, client: client}
  end

  describe "delete_checkpoint_by_tinker_path/2" do
    test "delegates to delete_checkpoint/2", %{client: client} do
      path = "tinker://run/checkpoint"
      assert {:ok, result} = RestClient.delete_checkpoint_by_tinker_path(client, path)
      assert result["deleted"] == true
      assert result["path"] == path
    end

    test "is equivalent to delete_checkpoint/2 with tinker path", %{client: client} do
      path = "tinker://user/model/checkpoint"

      result1 = RestClient.delete_checkpoint(client, path)
      result2 = RestClient.delete_checkpoint_by_tinker_path(client, path)

      assert result1 == result2
    end
  end

  describe "publish_checkpoint_from_tinker_path/2" do
    test "delegates to publish_checkpoint/2", %{client: client} do
      path = "tinker://run/checkpoint"
      assert {:ok, result} = RestClient.publish_checkpoint_from_tinker_path(client, path)
      assert result["published"] == true
      assert result["path"] == path
    end

    test "is equivalent to publish_checkpoint/2", %{client: client} do
      path = "tinker://user/model/checkpoint"

      result1 = RestClient.publish_checkpoint(client, path)
      result2 = RestClient.publish_checkpoint_from_tinker_path(client, path)

      assert result1 == result2
    end
  end

  describe "unpublish_checkpoint_from_tinker_path/2" do
    test "delegates to unpublish_checkpoint/2", %{client: client} do
      path = "tinker://run/checkpoint"
      assert {:ok, result} = RestClient.unpublish_checkpoint_from_tinker_path(client, path)
      assert result["unpublished"] == true
      assert result["path"] == path
    end

    test "is equivalent to unpublish_checkpoint/2", %{client: client} do
      path = "tinker://user/model/checkpoint"

      result1 = RestClient.unpublish_checkpoint(client, path)
      result2 = RestClient.unpublish_checkpoint_from_tinker_path(client, path)

      assert result1 == result2
    end
  end

  describe "get_checkpoint_archive_url_by_tinker_path/2" do
    test "delegates to get_checkpoint_archive_url/2", %{client: client} do
      path = "tinker://run/checkpoint"
      assert {:ok, result} = RestClient.get_checkpoint_archive_url_by_tinker_path(client, path)
      assert result.url =~ path
    end

    test "is equivalent to get_checkpoint_archive_url/2 with tinker path", %{client: client} do
      path = "tinker://user/model/checkpoint"

      result1 = RestClient.get_checkpoint_archive_url(client, path)
      result2 = RestClient.get_checkpoint_archive_url_by_tinker_path(client, path)

      assert result1 == result2
    end
  end

  # Async variants

  describe "delete_checkpoint_by_tinker_path_async/2" do
    test "returns a Task", %{client: client} do
      task = RestClient.delete_checkpoint_by_tinker_path_async(client, "tinker://path")
      assert %Task{} = task
    end

    test "task resolves to same result as sync version", %{client: client} do
      path = "tinker://run/checkpoint"

      sync_result = RestClient.delete_checkpoint_by_tinker_path(client, path)
      async_result = Task.await(RestClient.delete_checkpoint_by_tinker_path_async(client, path))

      assert sync_result == async_result
    end
  end

  describe "publish_checkpoint_from_tinker_path_async/2" do
    test "returns a Task", %{client: client} do
      task = RestClient.publish_checkpoint_from_tinker_path_async(client, "tinker://path")
      assert %Task{} = task
    end

    test "task resolves to same result as sync version", %{client: client} do
      path = "tinker://run/checkpoint"

      sync_result = RestClient.publish_checkpoint_from_tinker_path(client, path)

      async_result =
        Task.await(RestClient.publish_checkpoint_from_tinker_path_async(client, path))

      assert sync_result == async_result
    end
  end

  describe "unpublish_checkpoint_from_tinker_path_async/2" do
    test "returns a Task", %{client: client} do
      task = RestClient.unpublish_checkpoint_from_tinker_path_async(client, "tinker://path")
      assert %Task{} = task
    end

    test "task resolves to same result as sync version", %{client: client} do
      path = "tinker://run/checkpoint"

      sync_result = RestClient.unpublish_checkpoint_from_tinker_path(client, path)

      async_result =
        Task.await(RestClient.unpublish_checkpoint_from_tinker_path_async(client, path))

      assert sync_result == async_result
    end
  end

  describe "get_checkpoint_archive_url_by_tinker_path_async/2" do
    test "returns a Task", %{client: client} do
      task = RestClient.get_checkpoint_archive_url_by_tinker_path_async(client, "tinker://path")
      assert %Task{} = task
    end

    test "task resolves to same result as sync version", %{client: client} do
      path = "tinker://run/checkpoint"

      sync_result = RestClient.get_checkpoint_archive_url_by_tinker_path(client, path)

      async_result =
        Task.await(RestClient.get_checkpoint_archive_url_by_tinker_path_async(client, path))

      assert sync_result == async_result
    end
  end
end
