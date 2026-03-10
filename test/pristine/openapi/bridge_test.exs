defmodule Pristine.OpenAPI.BridgeTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Bridge

  @notion_reference_root "/home/home/p/g/n/jido_brainstorm/nshkrdotcom/notion_docs/reference"
  @proof_pages [
    "get-self.md",
    "create-a-token.md",
    "create-a-file-upload.md",
    "send-a-file-upload.md"
  ]

  test "processes official Notion docs snippets through oapi_generator" do
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
             :upload_file
           ]

    assert map_size(state.schemas) > 20

    sources = Bridge.generated_sources(state)

    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/users.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/file_uploads.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/o_auth.ex"))

    assert Enum.any?(Map.values(sources), &String.contains?(&1, "Pristine.OpenAPI.Client"))

    compile_generated_sources!(sources)

    users_module = Module.concat([base_module, Users])
    oauth_module = Module.concat([base_module, OAuth])
    file_uploads_module = Module.concat([base_module, FileUploads])

    assert {:ok, get_self_request} = apply(users_module, :get_self, [[]])
    assert get_self_request.method == :get
    assert get_self_request.url == "/v1/users/me"
    assert get_self_request.args == []

    assert {:ok, token_request} = apply(oauth_module, :create_a_token, [%{}, []])
    assert token_request.method == :post
    assert token_request.url == "/v1/oauth/token"
    assert token_request.request == [{"application/json", :map}]

    assert {:ok, upload_request} =
             apply(file_uploads_module, :upload_file, ["file-upload-id", %{}, []])

    assert upload_request.method == :post
    assert upload_request.url == "/v1/file_uploads/file-upload-id/send"
    assert upload_request.request == [{"multipart/form-data", :map}]
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

    assert {:ok, alias_request} = apply(users_module, :get_self_alias, [[]])
    assert alias_request.url == "/v1/users/me/alias"
    assert alias_request.method == :get
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
