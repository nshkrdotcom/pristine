defmodule Pristine.OpenAPI.OperationTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Operation

  test "partition/2 splits params into request concerns with string keys" do
    partition =
      Operation.partition(
        %{
          "start_cursor" => "cursor-1",
          file_upload_id: "upload-123",
          page_size: 50,
          grant_type: "refresh_token",
          refresh_token: "refresh-123",
          file: %{filename: "report.pdf", data: "bytes"},
          part_number: "2",
          auth: %{client_id: "client-id", client_secret: "client-secret"}
        },
        %{
          auth: {"auth", :auth},
          path: [{"file_upload_id", :file_upload_id}],
          query: [{"start_cursor", :start_cursor}, {"page_size", :page_size}],
          body: %{
            mode: :keys,
            keys: [{"grant_type", :grant_type}, {"refresh_token", :refresh_token}]
          },
          form_data: %{mode: :keys, keys: [{"file", :file}, {"part_number", :part_number}]}
        }
      )

    assert partition.path_params == %{"file_upload_id" => "upload-123"}
    assert partition.query == %{"page_size" => 50, "start_cursor" => "cursor-1"}
    assert partition.body == %{"grant_type" => "refresh_token", "refresh_token" => "refresh-123"}

    assert partition.form_data == %{
             "file" => %{filename: "report.pdf", data: "bytes"},
             "part_number" => "2"
           }

    assert partition.auth == %{client_id: "client-id", client_secret: "client-secret"}
  end

  test "partition/2 falls back to reserved body and form_data keys when field names are unavailable" do
    partition =
      Operation.partition(
        %{
          body: %{"raw" => true},
          form_data: %{"chunk" => 1}
        },
        %{
          auth: {"auth", :auth},
          path: [],
          query: [],
          body: %{mode: :key, key: {"body", :body}},
          form_data: %{mode: :key, key: {"form_data", :form_data}}
        }
      )

    assert partition.body == %{"raw" => true}
    assert partition.form_data == %{"chunk" => 1}
  end

  test "render_path/2 interpolates required path params" do
    assert Operation.render_path(
             "/v1/file_uploads/{file_upload_id}/send",
             %{"file_upload_id" => "upload-123"}
           ) == "/v1/file_uploads/upload-123/send"
  end

  test "render_path/2 raises when a required path param is missing" do
    assert_raise KeyError, fn ->
      Operation.render_path("/v1/users/{user_id}", %{})
    end
  end
end
