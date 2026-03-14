defmodule Pristine.OpenAPI.BridgeTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Url
  alias Pristine.OpenAPI.Bridge
  alias Pristine.OpenAPI.Client, as: OpenAPIClient
  alias Pristine.OpenAPI.NamedTypedMapFixture
  alias Pristine.OpenAPI.RendererMetadata
  alias Pristine.OpenAPI.Result

  @reference_root Path.expand("../../fixtures/openapi/bridge/reference", __DIR__)
  @proof_pages [
    "get-account-profile.md",
    "list-projects.md",
    "create-session-token.md",
    "create-upload.md",
    "send-upload-part.md"
  ]

  test "processes committed markdown OpenAPI snippets through the pristine bridge profile" do
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
        extract_openapi_fixture!(reference_fixture!(page), tmp_dir)
      end)

    state =
      Bridge.run(profile, spec_files,
        base_module: base_module,
        output_dir: output_dir
      )

    assert %Result{} = state
    assert Bridge.generator_state(state).operations == state.operations
    assert state.source_contexts == %{}
    assert Enum.any?(state.docs_manifest["operations"], &(&1["path"] == "/v1/accounts/me"))

    assert Enum.any?(
             state.docs_manifest["modules"],
             &String.ends_with?(&1["module"], ".Accounts")
           )

    assert Enum.sort(Enum.map(state.operations, & &1.function_name)) == [
             :create_session_token,
             :create_upload,
             :get_account_profile,
             :list_projects,
             :upload_part
           ]

    sources = Bridge.generated_sources(state)

    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/accounts.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/projects.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/uploads.ex"))
    assert Enum.any?(Map.keys(sources), &String.ends_with?(&1, "/session_tokens.ex"))

    assert Enum.any?(
             Map.keys(sources),
             &String.ends_with?(&1, "/account_profile_response.ex")
           )

    assert Enum.any?(Map.values(sources), &String.contains?(&1, "Pristine.OpenAPI.Client"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "use Pristine.OpenAPI.Operation"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "def __schema__(type \\\\ :t)"))
    assert Enum.any?(Map.values(sources), &String.contains?(&1, "def decode(data, type \\\\ :t)"))

    assert Enum.any?(
             Map.values(sources),
             &String.contains?(&1, "alias Pristine.OpenAPI.Runtime, as: OpenAPIRuntime")
           )

    assert Enum.any?(Map.values(sources), &String.contains?(&1, "OpenAPIRuntime.build_schema"))

    assert Enum.any?(
             Map.values(sources),
             &String.contains?(&1, "OpenAPIRuntime.decode_module_type")
           )

    refute Enum.any?(
             Map.values(sources),
             &String.contains?(&1, "Pristine.OpenAPI.Runtime.build_schema")
           )

    refute Enum.any?(
             Map.values(sources),
             &String.contains?(&1, "Pristine.OpenAPI.Runtime.decode_module_type")
           )

    compile_generated_sources!(sources)

    accounts_module = Module.concat([base_module, Accounts])
    projects_module = Module.concat([base_module, Projects])
    session_tokens_module = Module.concat([base_module, SessionTokens])
    uploads_module = Module.concat([base_module, Uploads])
    account_profile_module = Module.concat([base_module, AccountProfileResponse])

    assert function_exported?(accounts_module, :get_account_profile, 1)
    assert function_exported?(accounts_module, :get_account_profile, 2)
    assert function_exported?(projects_module, :list_projects, 1)
    assert function_exported?(projects_module, :list_projects, 2)
    assert function_exported?(session_tokens_module, :create_session_token, 1)
    assert function_exported?(session_tokens_module, :create_session_token, 2)
    assert function_exported?(uploads_module, :create_upload, 1)
    assert function_exported?(uploads_module, :create_upload, 2)
    assert function_exported?(uploads_module, :upload_part, 1)
    assert function_exported?(uploads_module, :upload_part, 2)
    assert function_exported?(account_profile_module, :__schema__, 1)
    assert function_exported?(account_profile_module, :decode, 1)
    assert %Sinter.Schema{} = account_profile_module.__schema__(:t)

    assert {:ok, decoded_account_profile} =
             account_profile_module.decode(%{
               "id" => "01234567-89ab-cdef-0123-456789abcdef",
               "kind" => "account"
             })

    assert decoded_account_profile.__struct__ == account_profile_module

    assert {:ok, profile_request} =
             accounts_module.get_account_profile(%{auth: "secret-token"}, [])

    assert profile_request.method == :get
    assert profile_request.path_template == "/v1/accounts/me"
    assert profile_request.url == "/v1/accounts/me"
    assert profile_request.args == %{auth: "secret-token"}
    assert profile_request.path_params == %{}
    assert profile_request.query == %{}
    assert profile_request.body == %{}
    assert profile_request.form_data == %{}
    assert profile_request.auth == "secret-token"
    assert profile_request.security == [%{"bearerAuth" => []}]

    assert {:ok, list_projects_request} =
             projects_module.list_projects(%{cursor: "cursor-1", page_size: 50}, [])

    assert list_projects_request.method == :get
    assert list_projects_request.path_template == "/v1/projects"
    assert list_projects_request.url == "/v1/projects"
    assert list_projects_request.path_params == %{}
    assert list_projects_request.query == %{"cursor" => "cursor-1", "page_size" => 50}
    assert list_projects_request.body == %{}
    assert list_projects_request.form_data == %{}

    assert {:ok, token_request} =
             session_tokens_module.create_session_token(
               %{
                 grant_type: "refresh_token",
                 refresh_token: "refresh-token",
                 auth: %{client_id: "client-id", client_secret: "client-secret"}
               },
               []
             )

    assert token_request.method == :post
    assert token_request.path_template == "/v1/session_tokens"
    assert token_request.url == "/v1/session_tokens"
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
             uploads_module.upload_part(
               %{
                 upload_id: "upload-id",
                 file: %{filename: "report.pdf", data: "bytes"},
                 part_number: "1",
                 auth: "secret-token"
               },
               []
             )

    assert upload_request.method == :post
    assert upload_request.path_template == "/v1/uploads/{upload_id}/parts"
    assert upload_request.url == "/v1/uploads/upload-id/parts"
    assert upload_request.path_params == %{"upload_id" => "upload-id"}
    assert upload_request.query == %{}
    assert upload_request.body == %{}

    assert upload_request.form_data == %{
             "file" => %{filename: "report.pdf", data: "bytes"},
             "part_number" => "1"
           }

    assert upload_request.auth == "secret-token"
    assert upload_request.request == [{"multipart/form-data", :map}]
    assert upload_request.security == [%{"bearerAuth" => []}]

    assert {:ok, encoded_upload_request} =
             uploads_module.upload_part(
               %{
                 upload_id: "folder/name",
                 file: %{filename: "report.pdf", data: "bytes"},
                 part_number: "1",
                 auth: "secret-token"
               },
               []
             )

    assert encoded_upload_request.path_template == "/v1/uploads/{upload_id}/parts"
    assert encoded_upload_request.url == "/v1/uploads/folder%2Fname/parts"

    spec = OpenAPIClient.to_request_spec(encoded_upload_request)

    assert spec.path == "/v1/uploads/{upload_id}/parts"

    assert Url.build(
             "https://example.com",
             spec.path,
             spec.path_params,
             spec.query
           ) == "https://example.com/v1/uploads/folder%2Fname/parts"
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
      extract_openapi_fixture!(reference_fixture!("get-account-profile.md"), tmp_dir)

    supplemental_spec = write_supplemental_spec!(tmp_dir)

    state =
      Bridge.run(profile, [primary_spec],
        base_module: base_module,
        output_dir: output_dir,
        supplemental_files: [supplemental_spec]
      )

    assert Enum.sort(Enum.map(state.operations, & &1.function_name)) == [
             :get_account_profile,
             :get_account_profile_alias
           ]

    sources = Bridge.generated_sources(state)
    compile_generated_sources!(sources)

    accounts_module = Module.concat([base_module, Accounts])

    assert {:ok, alias_request} = accounts_module.get_account_profile_alias(%{}, [])
    assert alias_request.url == "/v1/accounts/me/alias"
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
      extract_openapi_fixture!(reference_fixture!("get-account-profile.md"), tmp_dir)

    supplemental_spec = write_supplemental_spec!(tmp_dir, include_components?: false)

    assert_raise KeyError, fn ->
      Bridge.run(profile, [primary_spec],
        base_module: base_module,
        output_dir: output_dir,
        supplemental_files: [supplemental_spec]
      )
    end
  end

  test "passes source contexts through the canonical result and shared docs seam" do
    tmp_dir = tmp_dir!("source-contexts")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:source_contexts)
    base_module = unique_base_module(:source_contexts)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    spec_file =
      extract_openapi_fixture!(reference_fixture!("get-account-profile.md"), tmp_dir)

    state =
      Bridge.run(profile, [spec_file],
        base_module: base_module,
        output_dir: output_dir,
        source_contexts: %{
          {:get, "/v1/accounts/me"} => %{
            title: "Get account profile reference",
            description: "Reference page for retrieving the current account profile.",
            url: "https://docs.example.com/get-account-profile"
          }
        }
      )

    assert %Pristine.OpenAPI.IR.SourceContext{title: "Get account profile reference"} =
             state.source_contexts[{:get, "/v1/accounts/me"}]

    [operation_entry] =
      Enum.filter(state.docs_manifest["operations"], &(&1["path"] == "/v1/accounts/me"))

    assert operation_entry["doc"] =~ "## Source Context"
    assert operation_entry["doc"] =~ "Get account profile reference"

    accounts_source =
      Enum.find_value(Bridge.generated_sources(state), fn {path, source} ->
        if String.ends_with?(path, "/accounts.ex"), do: source
      end)

    assert accounts_source =~ "## Operations"
    assert accounts_source =~ "Get account profile reference"
  end

  test "uses preserved security metadata on the normal path and exposes richer openapi fields" do
    tmp_dir = tmp_dir!("rich-metadata")
    output_dir = Path.join(tmp_dir, "generated")
    profile = unique_profile(:rich_metadata)
    base_module = unique_base_module(:rich_metadata)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(tmp_dir)
    end)

    spec_file = write_review_spec!(tmp_dir, include_security?: true)

    state =
      Bridge.run(profile, [spec_file],
        base_module: base_module,
        output_dir: output_dir,
        source_contexts: %{
          {:get, "/widgets"} => %{
            title: "Widgets reference",
            description: "Reference page for widgets.",
            url: "https://docs.example.com/widgets"
          }
        }
      )

    assert Application.get_env(:oapi_generator, profile)[:output][:security_metadata] == nil
    assert Application.get_env(:oapi_generator, profile)[:output][:schema_specs_by_path] == nil
    assert Application.get_env(:oapi_generator, profile)[:output][:spec_metadata_source] == nil
    assert RendererMetadata.get(profile) == []

    sources = Bridge.generated_sources(state)
    compile_generated_sources!(sources)

    widgets_module = Module.concat([base_module, Widgets])
    widget_schema_module = widget_schema_module(state, base_module)

    assert {:ok, request} = widgets_module.list_widgets(%{}, [])
    assert request.security == [%{"bearerAuth" => []}]

    [field] = widget_schema_module.__openapi_fields__(:t)

    assert field.description == "Widget name"
    assert field.default == "demo"
    assert field.required == true
    assert field.nullable == false
    assert field.deprecated == true
    assert field.read_only == true
    assert field.write_only == false
    assert field.example == "Demo"
    assert field.examples == ["Demo", "Alternate"]

    assert field.external_docs == %{
             description: "Field docs",
             url: "https://example.com/widgets#name"
           }

    assert field.extensions == %{"x-extra" => "field"}

    [operation_entry] = state.docs_manifest["operations"]
    assert operation_entry["doc"] =~ "## Source Context"

    widgets_source =
      Enum.find_value(sources, fn {path, source} ->
        if String.ends_with?(path, "/widgets.ex"), do: source
      end)

    assert widgets_source =~ "## Operations"
    assert widgets_source =~ "Widgets reference"
  end

  test "uses explicit security metadata only as a fallback path" do
    tmp_dir = tmp_dir!("security-fallback")
    spec_file = write_review_spec!(tmp_dir, include_security?: false)

    without_fallback =
      generate_review_modules!(spec_file,
        label: :security_without_fallback,
        tmp_dir: tmp_dir
      )

    assert {:ok, request_without_fallback} =
             without_fallback.operation_module.list_widgets(%{}, [])

    assert Map.get(request_without_fallback, :security) == nil

    with_fallback =
      generate_review_modules!(spec_file,
        label: :security_with_fallback,
        tmp_dir: tmp_dir,
        security_metadata: %{
          operations: %{{:get, "/widgets"} => [%{"bearerAuth" => []}]},
          security_schemes: %{"bearerAuth" => %{"scheme" => "bearer", "type" => "http"}},
          security: nil
        }
      )

    assert {:ok, request_with_fallback} = with_fallback.operation_module.list_widgets(%{}, [])
    assert request_with_fallback.security == [%{"bearerAuth" => []}]
  end

  test "compiles named typed-map modules referenced from public operation types" do
    fixture = NamedTypedMapFixture.run_bridge!(:bridge)
    on_exit(fn -> NamedTypedMapFixture.cleanup(fixture) end)

    compile_generated_sources!(fixture.sources)

    oauth_module = Module.concat([fixture.base_module, OAuth])
    user_module = Module.concat([fixture.base_module, User])
    workspace_module = Module.concat([fixture.base_module, Workspace])
    oauth_source = NamedTypedMapFixture.source!(fixture, "/o_auth.ex")
    user_source = NamedTypedMapFixture.source!(fixture, "/user.ex")
    workspace_source = NamedTypedMapFixture.source!(fixture, "/workspace.ex")

    assert Code.ensure_loaded?(oauth_module)
    assert Code.ensure_loaded?(user_module)
    assert Code.ensure_loaded?(workspace_module)
    assert function_exported?(user_module, :__schema__, 1)
    assert function_exported?(workspace_module, :__schema__, 1)
    assert oauth_source =~ "#{inspect(user_module)}.t()"
    assert oauth_source =~ "#{inspect(workspace_module)}.t()"
    assert user_source =~ "@type t ::"
    assert user_source =~ "def __openapi_fields__(:t)"
    assert user_source =~ "def __schema__(:t)"
    assert workspace_source =~ "@type t ::"
    assert workspace_source =~ "def __openapi_fields__(:t)"
    assert workspace_source =~ "def __schema__(:t)"
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

  defp reference_fixture!(name) when is_binary(name) do
    Path.join(@reference_root, name)
  end

  defp write_review_spec!(tmp_dir, opts) do
    path = Path.join(tmp_dir, "review-proof.yaml")

    security_block =
      if Keyword.get(opts, :include_security?, true) do
        [
          "      security:\n",
          "        - bearerAuth: []\n"
        ]
      else
        []
      end

    File.write!(
      path,
      [
        "openapi: 3.1.0\n",
        "info:\n",
        "  title: Bridge review proof\n",
        "  version: 1.0.0\n",
        "components:\n",
        "  securitySchemes:\n",
        "    bearerAuth:\n",
        "      type: http\n",
        "      scheme: bearer\n",
        "  schemas:\n",
        "    Widget:\n",
        "      title: Widget\n",
        "      description: Widget schema.\n",
        "      type: object\n",
        "      properties:\n",
        "        name:\n",
        "          type: string\n",
        "          description: Widget name\n",
        "          default: demo\n",
        "          deprecated: true\n",
        "          readOnly: true\n",
        "          writeOnly: false\n",
        "          example: Demo\n",
        "          examples:\n",
        "            - Demo\n",
        "            - Alternate\n",
        "          externalDocs:\n",
        "            description: Field docs\n",
        "            url: https://example.com/widgets#name\n",
        "          x-extra: field\n",
        "      required:\n",
        "        - name\n",
        "paths:\n",
        "  /widgets:\n",
        "    get:\n",
        "      tags:\n",
        "        - Widgets\n",
        "      summary: List widgets\n",
        "      description: Returns every widget.\n",
        "      operationId: list-widgets\n",
        security_block,
        "      responses:\n",
        "        '200':\n",
        "          description: Widget list\n",
        "          content:\n",
        "            application/json:\n",
        "              schema:\n",
        "                $ref: '#/components/schemas/Widget'\n"
      ]
    )

    path
  end

  defp write_supplemental_spec!(tmp_dir, opts \\ []) do
    path = Path.join(tmp_dir, "bridge-supplement.yaml")

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
          title: Bridge supplemental proof
          version: 1.0.0
        """,
        components_block,
        """
        paths:
          /v1/accounts/me/alias:
            get:
              tags:
                - Accounts
              summary: Retrieve the current account alias
              operationId: get-account-profile-alias
              responses:
                '200':
                  description: ''
                  content:
                    application/json:
                      schema:
                        $ref: './get-account-profile.yaml#/components/schemas/accountProfileResponse'
        """
      ]
    )

    path
  end

  defp widget_schema_module(state, base_module) do
    state
    |> Map.fetch!(:schemas)
    |> Map.values()
    |> Enum.find(&(&1.module_name == Widget))
    |> then(&Module.concat([base_module, &1.module_name]))
  end

  defp generate_review_modules!(spec_file, opts) do
    label = Keyword.fetch!(opts, :label)
    tmp_dir = Keyword.fetch!(opts, :tmp_dir)
    output_dir = Path.join(tmp_dir, "#{label}-generated")
    profile = unique_profile(label)
    base_module = unique_base_module(label)

    on_exit(fn ->
      Application.delete_env(:oapi_generator, profile)
      File.rm_rf!(output_dir)
    end)

    state =
      Bridge.run(
        profile,
        [spec_file],
        [
          base_module: base_module,
          output_dir: output_dir
        ] ++ Keyword.take(opts, [:security_metadata])
      )

    compile_generated_sources!(Bridge.generated_sources(state))

    %{
      state: state,
      operation_module: Module.concat([base_module, Widgets]),
      schema_module: widget_schema_module(state, base_module)
    }
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
