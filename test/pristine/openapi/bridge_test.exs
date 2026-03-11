defmodule Pristine.OpenAPI.BridgeTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Bridge

  @notion_reference_root "/home/home/p/g/n/jido_brainstorm/nshkrdotcom/notion_docs/reference"
  @proof_pages [
    "get-self.md",
    "get-users.md",
    "create-a-token.md",
    "create-a-file-upload.md",
    "send-a-file-upload.md"
  ]
  @parity_pages [
    "get-self.md",
    "get-user.md",
    "get-users.md",
    "post-page.md",
    "retrieve-a-page.md",
    "patch-page.md",
    "move-page.md",
    "retrieve-a-page-property.md",
    "retrieve-page-markdown.md",
    "update-page-markdown.md",
    "retrieve-a-block.md",
    "update-a-block.md",
    "delete-a-block.md",
    "get-block-children.md",
    "patch-block-children.md",
    "retrieve-a-data-source.md",
    "update-a-data-source.md",
    "query-a-data-source.md",
    "create-a-data-source.md",
    "list-data-source-templates.md",
    "retrieve-a-database.md",
    "update-a-database.md",
    "create-a-database.md",
    "post-search.md",
    "create-a-comment.md",
    "list-comments.md",
    "retrieve-comment.md",
    "create-a-file-upload.md",
    "list-file-uploads.md",
    "send-a-file-upload.md",
    "complete-a-file-upload.md",
    "retrieve-a-file-upload.md",
    "create-a-token.md",
    "revoke-token.md",
    "introspect-token.md"
  ]

  test "processes official Notion docs snippets through the pristine bridge profile" do
    tmp_dir = tmp_dir!("proof")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:proof)
    base_module = unique_base_module(:proof)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    spec_files =
      Enum.map(@proof_pages, fn page ->
        extract_openapi_fixture!(Path.join(@notion_reference_root, page), tmp_dir)
      end)

    state =
      Bridge.run(profile, spec_files,
        base_module: base_module,
        output_dir: output_dir
      )

    assert Enum.sort(Enum.map(state.operations, & &1.function_name)) == [
             :create_a_token,
             :create_file,
             :get_self,
             :get_users,
             :upload_file
           ]

    assert map_size(state.schemas) > 20

    sources = Bridge.generated_sources(state)

    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/users.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/file_uploads.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/o_auth.ex"))

    assert Enum.any?(
             Map.keys(sources),
             &String.ends_with?(&1, "/partial_user_object_response.ex")
           )

    assert Enum.any?(Map.values(sources), &String.contains?(&1, "Pristine.OpenAPI.Client"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "use Pristine.OpenAPI.Operation"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "def __schema__(type \\\\ :t)"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "def decode(data, type \\\\ :t)"))

    compile_generated_sources!(sources)

    users_module = Module.concat([base_module, Users])
    oauth_module = Module.concat([base_module, OAuth])
    file_uploads_module = Module.concat([base_module, FileUploads])
    partial_user_module = Module.concat([base_module, PartialUserObjectResponse])

    assert function_exported?(users_module, :get_self, 1)
    assert function_exported?(users_module, :get_self, 2)
    assert function_exported?(users_module, :get_users, 1)
    assert function_exported?(users_module, :get_users, 2)
    assert function_exported?(oauth_module, :create_a_token, 1)
    assert function_exported?(oauth_module, :create_a_token, 2)
    assert function_exported?(file_uploads_module, :upload_file, 1)
    assert function_exported?(file_uploads_module, :upload_file, 2)
    assert function_exported?(partial_user_module, :__schema__, 1)
    assert function_exported?(partial_user_module, :decode, 1)
    assert %Sinter.Schema{} = partial_user_module.__schema__(:t)

    assert {:ok, decoded_partial_user} =
             partial_user_module.decode(%{
               "id" => "01234567-89ab-cdef-0123-456789abcdef",
               "object" => "user"
             })

    assert decoded_partial_user.__struct__ == partial_user_module

    assert {:ok, get_self_request} = users_module.get_self(%{auth: "secret-token"}, [])

    assert get_self_request.method == :get
    assert get_self_request.url == "/v1/users/me"
    assert get_self_request.args == %{auth: "secret-token"}
    assert get_self_request.path_params == %{}
    assert get_self_request.query == %{}
    assert get_self_request.body == %{}
    assert get_self_request.form_data == %{}
    assert get_self_request.auth == "secret-token"
    assert get_self_request.security == [%{"bearerAuth" => []}]

    assert {:ok, list_users_request} =
             users_module.get_users(%{start_cursor: "cursor-1", page_size: 50}, [])

    assert list_users_request.method == :get
    assert list_users_request.url == "/v1/users"
    assert list_users_request.path_params == %{}
    assert list_users_request.query == %{"page_size" => 50, "start_cursor" => "cursor-1"}
    assert list_users_request.body == %{}
    assert list_users_request.form_data == %{}

    assert {:ok, token_request} =
             oauth_module.create_a_token(
               %{
                 grant_type: "refresh_token",
                 refresh_token: "refresh-token",
                 auth: %{client_id: "client-id", client_secret: "client-secret"}
               },
               []
             )

    assert token_request.method == :post
    assert token_request.url == "/v1/oauth/token"
    assert token_request.path_params == %{}
    assert token_request.query == %{}

    assert token_request.body == %{
             "grant_type" => "refresh_token",
             "refresh_token" => "refresh-token"
           }

    assert token_request.form_data == %{}
    assert token_request.auth == %{client_id: "client-id", client_secret: "client-secret"}
    assert token_request.request == [{"application/json", :map}]
    assert token_request.security == [%{"basicAuth" => []}]

    assert {:ok, upload_request} =
             file_uploads_module.upload_file(
               %{
                 file_upload_id: "file-upload-id",
                 file: %{filename: "report.pdf", data: "bytes"},
                 part_number: "1",
                 auth: "secret-token"
               },
               []
             )

    assert upload_request.method == :post
    assert upload_request.url == "/v1/file_uploads/file-upload-id/send"
    assert upload_request.path_params == %{"file_upload_id" => "file-upload-id"}
    assert upload_request.query == %{}
    assert upload_request.body == %{}

    assert upload_request.form_data == %{
             "file" => %{filename: "report.pdf", data: "bytes"},
             "part_number" => "1"
           }

    assert upload_request.auth == "secret-token"
    assert upload_request.request == [{"multipart/form-data", :map}]
    assert upload_request.security == [%{"bearerAuth" => []}]
  end

  test "accepts supplemental OpenAPI fragments through the bridge profile" do
    tmp_dir = tmp_dir!("supplemental")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:supplemental)
    base_module = unique_base_module(:supplemental)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    primary_spec =
      extract_openapi_fixture!(Path.join(@notion_reference_root, "get-self.md"), tmp_dir)

    supplemental_spec = write_supplemental_spec!(tmp_dir)

    state =
      Bridge.run(profile, [primary_spec],
        base_module: base_module,
        output_dir: output_dir,
        supplemental_files: [supplemental_spec]
      )

    assert Enum.sort(Enum.map(state.operations, & &1.function_name)) == [
             :get_self,
             :get_self_alias
           ]

    sources = Bridge.generated_sources(state)
    compile_generated_sources!(sources)

    users_module = Module.concat([base_module, Users])

    assert {:ok, alias_request} = users_module.get_self_alias(%{}, [])
    assert alias_request.url == "/v1/users/me/alias"
    assert alias_request.method == :get
  end

  test "represents the full 35-operation Notion endpoint surface" do
    tmp_dir = tmp_dir!("parity")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:parity)
    base_module = unique_base_module(:parity)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    spec_files =
      Enum.map(@parity_pages, fn page ->
        extract_openapi_fixture!(Path.join(@notion_reference_root, page), tmp_dir)
      end)

    state =
      Bridge.run(profile, spec_files,
        base_module: base_module,
        output_dir: output_dir
      )

    assert length(state.operations) == 35

    modules =
      state.operations
      |> Enum.map(& &1.module_name)
      |> Enum.uniq()
      |> Enum.sort()

    assert Users in modules
    assert Pages in modules
    assert Blocks in modules
    assert DataSources in modules
    assert Databases in modules
    assert Comments in modules
    assert FileUploads in modules
    assert OAuth in modules
    assert Search in modules
  end

  test "documents the upstream gap for supplemental roots without components" do
    tmp_dir = tmp_dir!("supplemental-gap")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:supplemental_gap)
    base_module = unique_base_module(:supplemental_gap)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    primary_spec =
      extract_openapi_fixture!(Path.join(@notion_reference_root, "get-self.md"), tmp_dir)

    supplemental_spec = write_supplemental_spec!(tmp_dir, include_components?: false)

    assert_raise KeyError, fn ->
      Bridge.run(profile, [primary_spec],
        base_module: base_module,
        output_dir: output_dir,
        supplemental_files: [supplemental_spec]
      )
    end
  end

  defp compile_generated_sources!(sources) do
    sources
    |> Enum.sort_by(fn {_path, source} ->
      if String.contains?(source, "client.request(%{"), do: 1, else: 0
    end)
    |> Enum.each(fn {path, source} ->
      Code.compile_string(source, path)
    end)
  end

  defp extract_openapi_fixture!(markdown_path, target_dir) do
    target_path =
      Path.join(target_dir, Path.rootname(Path.basename(markdown_path)) <> ".yaml")

    markdown = File.read!(markdown_path)

    yaml =
      case Regex.run(~r/````yaml[^\n]*\n(.*?)\n````/ms, markdown, capture: :all_but_first) do
        [yaml] ->
          yaml

        _ ->
          raise "unable to extract OpenAPI fixture from #{markdown_path}"
      end

    File.write!(target_path, yaml)
    target_path
  end

  defp write_supplemental_spec!(tmp_dir, opts \\ []) do
    path = Path.join(tmp_dir, "notion-supplement.yaml")

    components_block =
      if Keyword.get(opts, :include_components?, true) do
        "components: {}\n"
      else
        ""
      end

    File.write!(
      path,
      [
        """
        openapi: 3.1.0
        info:
          title: Notion supplemental proof
          version: 1.0.0
        """,
        components_block,
        """
        paths:
          /v1/users/me/alias:
            get:
              tags:
                - Users
              summary: Retrieve your token's bot user alias
              operationId: get-self-alias
              responses:
                '200':
                  description: ''
                  content:
                    application/json:
                      schema:
                        $ref: './get-self.yaml#/components/schemas/partialUserObjectResponse'
        """
      ]
    )

    path
  end

  defp tmp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "pristine-openapi-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp unique_profile(label) do
    :"pristine_openapi_bridge_#{label}_#{System.unique_integer([:positive])}"
  end

  defp unique_base_module(label) do
    Module.concat([
      Pristine,
      :"OpenAPIBridge#{label |> to_string() |> Macro.camelize()}#{System.unique_integer([:positive])}"
    ])
  end
end
