defmodule Pristine.OperationTest do
  use ExUnit.Case, async: true

  alias Pristine.Operation

  test "partition/2 splits params into runtime operation fields" do
    partition =
      Operation.partition(
        %{
          "id" => "widget-123",
          "cursor" => "cursor-1",
          "payload" => %{"name" => "Ada"}
        },
        %{
          path: [{"id", :id}],
          query: [{"cursor", :cursor}],
          body: %{mode: :key, key: {"payload", :payload}},
          form_data: %{mode: :none}
        }
      )

    assert partition.path_params == %{"id" => "widget-123"}
    assert partition.query == %{"cursor" => "cursor-1"}
    assert partition.body == %{"name" => "Ada"}
    assert is_nil(partition.form_data)
  end

  test "render_path/2 encodes reserved path characters" do
    assert Operation.render_path("/v1/widgets/{id}", %{"id" => "folder/item"}) ==
             "/v1/widgets/folder%2Fitem"
  end

  test "pagination helpers extract items and advance cursor operations" do
    operation =
      Operation.new(%{
        id: "widgets.list",
        method: :get,
        path_template: "/v1/widgets",
        pagination: %{
          strategy: :cursor,
          request_mapping: %{cursor_param: "cursor", limit_param: "page_size"},
          response_mapping: %{cursor_path: ["next_cursor"]},
          default_limit: 20,
          items_path: ["results"]
        }
      })

    response_body = %{
      "results" => [%{"id" => "widget-123"}],
      "next_cursor" => "cursor-2"
    }

    assert Operation.items(operation, response_body) == [%{"id" => "widget-123"}]

    assert %Operation{} = next_operation = Operation.next_page(operation, response_body)
    assert next_operation.query == %{"cursor" => "cursor-2", "page_size" => 20}
  end

  test "pagination helpers follow link headers for next-page traversal" do
    operation =
      Operation.new(%{
        id: "repos.list",
        method: :get,
        path_template: "/user/repos",
        query: %{"per_page" => 50},
        pagination: %{
          strategy: :link_header,
          request_mapping: %{limit_param: "per_page"},
          response_mapping: %{link_header: "link"},
          default_limit: 30,
          items_path: nil
        }
      })

    response = %Pristine.Response{
      status: 200,
      headers: %{
        "link" =>
          "<https://api.example.com/user/repos?page=2&per_page=50>; rel=\"next\", " <>
            "<https://api.example.com/user/repos?page=4&per_page=50>; rel=\"last\""
      },
      body: [%{"id" => 1}]
    }

    assert Operation.items(operation, response) == [%{"id" => 1}]

    assert %Operation{} = next_operation = Operation.next_page(operation, response)
    assert next_operation.path_template == "/user/repos"
    assert next_operation.query == %{"page" => "2", "per_page" => "50"}
  end
end
