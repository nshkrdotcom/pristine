# Stage 5: Developer Tooling Implementation

**Goal**: Complete developer experience with validation, docs, and testing tools.

**Dependencies**: Stages 1-3 must be completed first.

---

## Required Reading

### Architecture Audit Documents (Read First)

```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/gap-analysis.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/roadmap.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/07-cli-tools.md
```

### Pristine Source Files

```
/home/home/p/g/n/pristine/lib/pristine/manifest.ex
/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex
/home/home/p/g/n/pristine/lib/pristine/manifest/type_def.ex
/home/home/p/g/n/pristine/lib/pristine/codegen.ex
/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex
/home/home/p/g/n/pristine/lib/mix/tasks/pristine.validate.ex
```

### Sinter Source Files

```
/home/home/p/g/n/sinter/lib/sinter/schema.ex
/home/home/p/g/n/sinter/lib/sinter/json_schema.ex
```

### Reference Implementation (Tinker)

```
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_utils/_generate_examples.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_utils/_transform.py
```

### Existing Tinkex (Reference)

```
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/testing.ex
```

---

## Gaps Addressed

| Gap ID | Description |
|--------|-------------|
| GAP-014 | OpenAPI Spec Generation |
| GAP-023 | Documentation Generation |
| GAP-024 | Test Fixtures Module |
| GAP-025 | Mock Server Generation |

---

## Task 5.1: OpenAPI Spec Generation

### Context

Pristine manifests define APIs declaratively but currently cannot export to standard OpenAPI format. This prevents integration with ecosystem tools like Swagger UI, API documentation generators, and testing tools.

### Files to Create

- `/home/home/p/g/n/pristine/lib/pristine/openapi.ex`
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.openapi.ex`
- `/home/home/p/g/n/pristine/test/pristine/openapi_test.exs`
- `/home/home/p/g/n/pristine/test/mix/tasks/pristine_openapi_test.exs`

### Tests First

Create `/home/home/p/g/n/pristine/test/pristine/openapi_test.exs`:

```elixir
defmodule Pristine.OpenAPITest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI
  alias Pristine.Manifest

  describe "generate/2" do
    test "generates valid OpenAPI 3.1 structure" do
      manifest = build_test_manifest()

      {:ok, spec} = OpenAPI.generate(manifest)

      assert spec["openapi"] == "3.1.0"
      assert is_map(spec["info"])
      assert is_map(spec["paths"])
      assert is_map(spec["components"])
    end

    test "includes info section from manifest metadata" do
      manifest = build_test_manifest(%{
        name: "TestAPI",
        version: "1.0.0",
        description: "Test API description"
      })

      {:ok, spec} = OpenAPI.generate(manifest)

      assert spec["info"]["title"] == "TestAPI"
      assert spec["info"]["version"] == "1.0.0"
      assert spec["info"]["description"] == "Test API description"
    end

    test "generates paths from endpoints" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"},
        %{id: :create_user, method: :post, path: "/users"}
      ])

      {:ok, spec} = OpenAPI.generate(manifest)

      assert Map.has_key?(spec["paths"], "/users/{id}")
      assert Map.has_key?(spec["paths"]["/users/{id}"], "get")
      assert Map.has_key?(spec["paths"], "/users")
      assert Map.has_key?(spec["paths"]["/users"], "post")
    end

    test "generates path parameters from endpoint path" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{user_id}/posts/{post_id}"}
      ])

      {:ok, spec} = OpenAPI.generate(manifest)

      params = spec["paths"]["/users/{user_id}/posts/{post_id}"]["get"]["parameters"]
      param_names = Enum.map(params, & &1["name"])

      assert "user_id" in param_names
      assert "post_id" in param_names
      assert Enum.all?(params, & &1["in"] == "path")
    end

    test "generates request body schema from endpoint request_type" do
      manifest = build_test_manifest_with_typed_endpoint(:create_user, %{
        method: :post,
        path: "/users",
        request_type: :user_create_request
      })

      {:ok, spec} = OpenAPI.generate(manifest)

      body = spec["paths"]["/users"]["post"]["requestBody"]
      assert body["required"] == true
      assert is_map(body["content"]["application/json"]["schema"])
    end

    test "generates response schemas from endpoint response_type" do
      manifest = build_test_manifest_with_typed_endpoint(:get_user, %{
        method: :get,
        path: "/users/{id}",
        response_type: :user
      })

      {:ok, spec} = OpenAPI.generate(manifest)

      responses = spec["paths"]["/users/{id}"]["get"]["responses"]
      assert is_map(responses["200"])
      assert is_map(responses["200"]["content"]["application/json"]["schema"])
    end

    test "generates components/schemas from manifest types" do
      manifest = build_test_manifest_with_types([
        %{id: :user, schema: user_schema()},
        %{id: :post, schema: post_schema()}
      ])

      {:ok, spec} = OpenAPI.generate(manifest)

      schemas = spec["components"]["schemas"]
      assert Map.has_key?(schemas, "User")
      assert Map.has_key?(schemas, "Post")
    end

    test "uses $ref for type references" do
      manifest = build_test_manifest_with_typed_endpoint(:get_user, %{
        method: :get,
        path: "/users/{id}",
        response_type: :user
      })

      {:ok, spec} = OpenAPI.generate(manifest)

      schema = spec["paths"]["/users/{id}"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
      assert schema["$ref"] == "#/components/schemas/User"
    end

    test "generates discriminated unions as oneOf with discriminator" do
      manifest = build_test_manifest_with_types([
        %{id: :content_block, schema: discriminated_content_schema()}
      ])

      {:ok, spec} = OpenAPI.generate(manifest)

      schema = spec["components"]["schemas"]["ContentBlock"]
      assert is_list(schema["oneOf"])
      assert is_map(schema["discriminator"])
      assert schema["discriminator"]["propertyName"] == "type"
    end

    test "includes server URLs from manifest base_url" do
      manifest = build_test_manifest(%{
        base_url: "https://api.example.com/v1"
      })

      {:ok, spec} = OpenAPI.generate(manifest)

      assert [%{"url" => "https://api.example.com/v1"}] = spec["servers"]
    end

    test "generates security schemes from manifest auth config" do
      manifest = build_test_manifest_with_auth(:bearer)

      {:ok, spec} = OpenAPI.generate(manifest)

      security = spec["components"]["securitySchemes"]
      assert security["bearerAuth"]["type"] == "http"
      assert security["bearerAuth"]["scheme"] == "bearer"
    end

    test "formats output as JSON string with pretty option" do
      manifest = build_test_manifest()

      {:ok, json} = OpenAPI.generate(manifest, format: :json)

      assert is_binary(json)
      assert {:ok, _} = Jason.decode(json)
    end

    test "formats output as YAML string with yaml option" do
      manifest = build_test_manifest()

      {:ok, yaml} = OpenAPI.generate(manifest, format: :yaml)

      assert is_binary(yaml)
      assert String.starts_with?(yaml, "openapi:")
    end
  end

  describe "schema_to_openapi/1" do
    test "converts string type" do
      schema = %{type: :string}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "string"}
    end

    test "converts string with format" do
      schema = %{type: :string, format: :email}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "string", "format" => "email"}
    end

    test "converts integer type" do
      schema = %{type: :integer}
      assert OpenAPI.schema_to_openapi(schema) == %{"type" => "integer"}
    end

    test "converts integer with minimum/maximum" do
      schema = %{type: :integer, minimum: 1, maximum: 100}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "integer"
      assert result["minimum"] == 1
      assert result["maximum"] == 100
    end

    test "converts array type" do
      schema = %{type: {:array, :string}}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "array"
      assert result["items"] == %{"type" => "string"}
    end

    test "converts map type with properties" do
      schema = %{
        type: :map,
        properties: [
          {:name, :string, [required: true]},
          {:age, :integer, []}
        ]
      }
      result = OpenAPI.schema_to_openapi(schema)
      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["required"] == ["name"]
    end

    test "converts literal type to const" do
      schema = %{type: {:literal, "fixed_value"}}
      result = OpenAPI.schema_to_openapi(schema)
      assert result["const"] == "fixed_value"
    end

    test "converts union type to oneOf" do
      schema = %{type: {:union, [:string, :integer]}}
      result = OpenAPI.schema_to_openapi(schema)
      assert is_list(result["oneOf"])
      assert %{"type" => "string"} in result["oneOf"]
      assert %{"type" => "integer"} in result["oneOf"]
    end
  end

  # Helper functions to build test manifests
  defp build_test_manifest(attrs \\ %{}), do: ...
  defp build_test_manifest_with_endpoints(endpoints), do: ...
  defp build_test_manifest_with_typed_endpoint(id, attrs), do: ...
  defp build_test_manifest_with_types(types), do: ...
  defp build_test_manifest_with_auth(scheme), do: ...
  defp user_schema, do: ...
  defp post_schema, do: ...
  defp discriminated_content_schema, do: ...
end
```

Create `/home/home/p/g/n/pristine/test/mix/tasks/pristine_openapi_test.exs`:

```elixir
defmodule Mix.Tasks.Pristine.OpenapiTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  describe "run/1" do
    test "generates OpenAPI spec to stdout", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)

      output = capture_io(fn ->
        Mix.Tasks.Pristine.Openapi.run(["--manifest", manifest_path])
      end)

      assert output =~ "openapi"
      assert {:ok, _} = Jason.decode(output)
    end

    test "writes to file with --output option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "openapi.json")

      Mix.Tasks.Pristine.Openapi.run([
        "--manifest", manifest_path,
        "--output", output_path
      ])

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert {:ok, spec} = Jason.decode(content)
      assert spec["openapi"] == "3.1.0"
    end

    test "generates YAML with --format yaml option", %{tmp_dir: tmp_dir} do
      manifest_path = create_test_manifest(tmp_dir)
      output_path = Path.join(tmp_dir, "openapi.yaml")

      Mix.Tasks.Pristine.Openapi.run([
        "--manifest", manifest_path,
        "--output", output_path,
        "--format", "yaml"
      ])

      content = File.read!(output_path)
      assert content =~ "openapi: \"3.1.0\""
    end

    test "exits with error for invalid manifest", %{tmp_dir: tmp_dir} do
      invalid_path = Path.join(tmp_dir, "invalid.json")
      File.write!(invalid_path, "not valid json")

      assert_raise Mix.Error, fn ->
        Mix.Tasks.Pristine.Openapi.run(["--manifest", invalid_path])
      end
    end

    test "requires --manifest option" do
      assert_raise Mix.Error, ~r/--manifest.*required/, fn ->
        Mix.Tasks.Pristine.Openapi.run([])
      end
    end
  end

  defp create_test_manifest(dir) do
    path = Path.join(dir, "manifest.json")
    manifest = %{
      "name" => "TestAPI",
      "version" => "1.0.0",
      "base_url" => "https://api.example.com",
      "endpoints" => [],
      "types" => []
    }
    File.write!(path, Jason.encode!(manifest))
    path
  end
end
```

### Implementation

Create `/home/home/p/g/n/pristine/lib/pristine/openapi.ex`:

```elixir
defmodule Pristine.OpenAPI do
  @moduledoc """
  Generates OpenAPI 3.1 specifications from Pristine manifests.

  ## Usage

      {:ok, spec} = Pristine.OpenAPI.generate(manifest)
      {:ok, json} = Pristine.OpenAPI.generate(manifest, format: :json)
      {:ok, yaml} = Pristine.OpenAPI.generate(manifest, format: :yaml)
  """

  alias Pristine.Manifest
  alias Pristine.Manifest.{Endpoint, TypeDef}

  @openapi_version "3.1.0"

  @type format :: :map | :json | :yaml
  @type option :: {:format, format}

  @spec generate(Manifest.t(), [option]) :: {:ok, map() | String.t()} | {:error, term()}
  def generate(%Manifest{} = manifest, opts \\ []) do
    format = Keyword.get(opts, :format, :map)

    spec = %{
      "openapi" => @openapi_version,
      "info" => build_info(manifest),
      "servers" => build_servers(manifest),
      "paths" => build_paths(manifest),
      "components" => build_components(manifest)
    }
    |> maybe_add_security(manifest)

    format_output(spec, format)
  end

  @spec schema_to_openapi(map()) :: map()
  def schema_to_openapi(schema) when is_map(schema) do
    convert_schema(schema)
  end

  # Private functions

  defp build_info(%Manifest{} = manifest) do
    %{
      "title" => manifest.name || "API",
      "version" => manifest.version || "1.0.0"
    }
    |> maybe_put("description", manifest.description)
  end

  defp build_servers(%Manifest{base_url: nil}), do: []
  defp build_servers(%Manifest{base_url: url}), do: [%{"url" => url}]

  defp build_paths(%Manifest{endpoints: endpoints}) do
    endpoints
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {path, path_endpoints} ->
      {path, build_path_item(path_endpoints)}
    end)
    |> Map.new()
  end

  defp build_path_item(endpoints) do
    endpoints
    |> Enum.map(fn endpoint ->
      {method_string(endpoint.method), build_operation(endpoint)}
    end)
    |> Map.new()
  end

  defp build_operation(%Endpoint{} = endpoint) do
    %{
      "operationId" => to_string(endpoint.id)
    }
    |> maybe_put("summary", endpoint.summary)
    |> maybe_put("description", endpoint.description)
    |> maybe_put("parameters", build_parameters(endpoint))
    |> maybe_put("requestBody", build_request_body(endpoint))
    |> Map.put("responses", build_responses(endpoint))
  end

  defp build_parameters(%Endpoint{path: path} = endpoint) do
    path_params = extract_path_params(path)
    query_params = endpoint.query_params || []
    header_params = endpoint.header_params || []

    params =
      build_path_params(path_params) ++
      build_query_params(query_params) ++
      build_header_params(header_params)

    if Enum.empty?(params), do: nil, else: params
  end

  defp extract_path_params(path) do
    ~r/\{([^}]+)\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp build_path_params(names) do
    Enum.map(names, fn name ->
      %{
        "name" => name,
        "in" => "path",
        "required" => true,
        "schema" => %{"type" => "string"}
      }
    end)
  end

  defp build_query_params(params) do
    Enum.map(params, fn {name, opts} ->
      %{
        "name" => to_string(name),
        "in" => "query",
        "required" => Keyword.get(opts, :required, false),
        "schema" => schema_to_openapi(Keyword.get(opts, :type, :string))
      }
    end)
  end

  defp build_header_params(params) do
    Enum.map(params, fn {name, opts} ->
      %{
        "name" => to_string(name),
        "in" => "header",
        "required" => Keyword.get(opts, :required, false),
        "schema" => schema_to_openapi(Keyword.get(opts, :type, :string))
      }
    end)
  end

  defp build_request_body(%Endpoint{request_type: nil}), do: nil
  defp build_request_body(%Endpoint{request_type: type_id}) do
    %{
      "required" => true,
      "content" => %{
        "application/json" => %{
          "schema" => %{"$ref" => type_ref(type_id)}
        }
      }
    }
  end

  defp build_responses(%Endpoint{response_type: nil}) do
    %{"200" => %{"description" => "Success"}}
  end
  defp build_responses(%Endpoint{response_type: type_id}) do
    %{
      "200" => %{
        "description" => "Success",
        "content" => %{
          "application/json" => %{
            "schema" => %{"$ref" => type_ref(type_id)}
          }
        }
      }
    }
  end

  defp build_components(%Manifest{types: types}) do
    schemas =
      types
      |> Enum.map(fn %TypeDef{id: id, schema: schema} ->
        {type_name(id), convert_schema(schema)}
      end)
      |> Map.new()

    %{
      "schemas" => schemas
    }
  end

  defp convert_schema(%{type: :string} = schema) do
    %{"type" => "string"}
    |> maybe_put("format", schema[:format])
    |> maybe_put("minLength", schema[:min_length])
    |> maybe_put("maxLength", schema[:max_length])
    |> maybe_put("pattern", schema[:pattern])
  end

  defp convert_schema(%{type: :integer} = schema) do
    %{"type" => "integer"}
    |> maybe_put("minimum", schema[:minimum])
    |> maybe_put("maximum", schema[:maximum])
  end

  defp convert_schema(%{type: :number} = schema) do
    %{"type" => "number"}
    |> maybe_put("minimum", schema[:minimum])
    |> maybe_put("maximum", schema[:maximum])
  end

  defp convert_schema(%{type: :boolean}), do: %{"type" => "boolean"}

  defp convert_schema(%{type: {:array, item_type}}) do
    %{
      "type" => "array",
      "items" => convert_schema(%{type: item_type})
    }
  end

  defp convert_schema(%{type: {:literal, value}}) do
    %{"const" => value}
  end

  defp convert_schema(%{type: {:union, types}}) do
    %{
      "oneOf" => Enum.map(types, fn t -> convert_schema(%{type: t}) end)
    }
  end

  defp convert_schema(%{type: {:discriminated_union, opts}}) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    %{
      "oneOf" => Enum.map(variants, fn {_key, schema} ->
        convert_schema(schema)
      end),
      "discriminator" => %{
        "propertyName" => discriminator,
        "mapping" => build_discriminator_mapping(variants)
      }
    }
  end

  defp convert_schema(%{type: :map, properties: props}) do
    {properties, required} =
      Enum.reduce(props, {%{}, []}, fn {name, type, opts}, {props_acc, req_acc} ->
        prop_schema = convert_schema(%{type: type})
        new_props = Map.put(props_acc, to_string(name), prop_schema)
        new_req = if Keyword.get(opts, :required, false),
          do: [to_string(name) | req_acc],
          else: req_acc
        {new_props, new_req}
      end)

    result = %{
      "type" => "object",
      "properties" => properties
    }

    if Enum.empty?(required), do: result, else: Map.put(result, "required", Enum.reverse(required))
  end

  defp convert_schema(%{type: type}) when is_atom(type) do
    # Type reference
    %{"$ref" => type_ref(type)}
  end

  defp convert_schema(type) when is_atom(type) do
    case type do
      :string -> %{"type" => "string"}
      :integer -> %{"type" => "integer"}
      :number -> %{"type" => "number"}
      :boolean -> %{"type" => "boolean"}
      _ -> %{"$ref" => type_ref(type)}
    end
  end

  defp build_discriminator_mapping(variants) do
    variants
    |> Enum.map(fn {key, _schema} ->
      {to_string(key), "#/components/schemas/#{type_name(key)}"}
    end)
    |> Map.new()
  end

  defp maybe_add_security(spec, %Manifest{auth: nil}), do: spec
  defp maybe_add_security(spec, %Manifest{auth: :bearer}) do
    spec
    |> put_in(["components", "securitySchemes"], %{
      "bearerAuth" => %{
        "type" => "http",
        "scheme" => "bearer"
      }
    })
    |> Map.put("security", [%{"bearerAuth" => []}])
  end
  defp maybe_add_security(spec, %Manifest{auth: :api_key}) do
    spec
    |> put_in(["components", "securitySchemes"], %{
      "apiKey" => %{
        "type" => "apiKey",
        "in" => "header",
        "name" => "X-API-Key"
      }
    })
    |> Map.put("security", [%{"apiKey" => []}])
  end

  defp type_ref(type_id), do: "#/components/schemas/#{type_name(type_id)}"

  defp type_name(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> Macro.camelize()
  end

  defp method_string(:get), do: "get"
  defp method_string(:post), do: "post"
  defp method_string(:put), do: "put"
  defp method_string(:patch), do: "patch"
  defp method_string(:delete), do: "delete"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_output(spec, :map), do: {:ok, spec}
  defp format_output(spec, :json), do: {:ok, Jason.encode!(spec, pretty: true)}
  defp format_output(spec, :yaml) do
    yaml = to_yaml(spec, 0)
    {:ok, yaml}
  end

  # Simple YAML encoder (or use YamlElixir if available)
  defp to_yaml(map, indent) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      prefix = String.duplicate("  ", indent)
      "#{prefix}#{k}: #{to_yaml_value(v, indent)}"
    end)
    |> Enum.join("\n")
  end

  defp to_yaml_value(nil, _), do: "null"
  defp to_yaml_value(true, _), do: "true"
  defp to_yaml_value(false, _), do: "false"
  defp to_yaml_value(s, _) when is_binary(s), do: inspect(s)
  defp to_yaml_value(n, _) when is_number(n), do: to_string(n)
  defp to_yaml_value(list, indent) when is_list(list) do
    items = Enum.map(list, fn item ->
      prefix = String.duplicate("  ", indent + 1)
      "#{prefix}- #{to_yaml_value(item, indent + 1)}"
    end)
    "\n" <> Enum.join(items, "\n")
  end
  defp to_yaml_value(map, indent) when is_map(map) do
    "\n" <> to_yaml(map, indent + 1)
  end
end
```

Create `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.openapi.ex`:

```elixir
defmodule Mix.Tasks.Pristine.Openapi do
  @moduledoc """
  Generates OpenAPI specification from a Pristine manifest.

  ## Usage

      mix pristine.openapi --manifest path/to/manifest.json
      mix pristine.openapi --manifest path/to/manifest.json --output openapi.json
      mix pristine.openapi --manifest path/to/manifest.json --output openapi.yaml --format yaml

  ## Options

    * `--manifest` - Path to the Pristine manifest file (required)
    * `--output` - Output file path (default: stdout)
    * `--format` - Output format: json or yaml (default: json)
  """

  use Mix.Task

  @shortdoc "Generate OpenAPI spec from manifest"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [
      manifest: :string,
      output: :string,
      format: :string
    ])

    manifest_path = opts[:manifest] || raise_missing_manifest()
    output_path = opts[:output]
    format = parse_format(opts[:format])

    manifest = load_manifest!(manifest_path)

    case Pristine.OpenAPI.generate(manifest, format: format) do
      {:ok, spec} ->
        output_spec(spec, output_path)
      {:error, reason} ->
        Mix.raise("Failed to generate OpenAPI spec: #{inspect(reason)}")
    end
  end

  defp load_manifest!(path) do
    case Pristine.Manifest.load_file(path) do
      {:ok, manifest} -> manifest
      {:error, reason} -> Mix.raise("Failed to load manifest: #{inspect(reason)}")
    end
  end

  defp parse_format(nil), do: :json
  defp parse_format("json"), do: :json
  defp parse_format("yaml"), do: :yaml
  defp parse_format(other), do: Mix.raise("Unknown format: #{other}")

  defp output_spec(spec, nil), do: Mix.shell().info(spec)
  defp output_spec(spec, path) do
    File.write!(path, spec)
    Mix.shell().info("OpenAPI spec written to #{path}")
  end

  defp raise_missing_manifest do
    Mix.raise("--manifest option is required")
  end
end
```

---

## Task 5.2: Documentation Generation

### Context

Generate readable documentation from manifests, including endpoint descriptions, type schemas, and usage examples.

### Files to Create

- `/home/home/p/g/n/pristine/lib/pristine/docs.ex`
- `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.docs.ex`
- `/home/home/p/g/n/pristine/test/pristine/docs_test.exs`
- `/home/home/p/g/n/pristine/test/mix/tasks/pristine_docs_test.exs`

### Tests First

Create `/home/home/p/g/n/pristine/test/pristine/docs_test.exs`:

```elixir
defmodule Pristine.DocsTest do
  use ExUnit.Case, async: true

  alias Pristine.Docs
  alias Pristine.Manifest

  describe "generate/2" do
    test "generates markdown documentation" do
      manifest = build_test_manifest()

      {:ok, docs} = Docs.generate(manifest)

      assert is_binary(docs)
      assert docs =~ "# TestAPI"
    end

    test "includes API overview section" do
      manifest = build_test_manifest(%{
        name: "TestAPI",
        description: "API for testing",
        version: "1.0.0",
        base_url: "https://api.example.com"
      })

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Overview"
      assert docs =~ "API for testing"
      assert docs =~ "Base URL: `https://api.example.com`"
      assert docs =~ "Version: 1.0.0"
    end

    test "generates table of contents" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, resource: :users},
        %{id: :create_user, resource: :users},
        %{id: :list_posts, resource: :posts}
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Table of Contents"
      assert docs =~ "- [Users](#users)"
      assert docs =~ "- [Posts](#posts)"
    end

    test "groups endpoints by resource" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, resource: :users, method: :get, path: "/users/{id}"},
        %{id: :create_user, resource: :users, method: :post, path: "/users"}
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Users"
      assert docs =~ "### GET /users/{id}"
      assert docs =~ "### POST /users"
    end

    test "includes endpoint description" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, description: "Retrieves a user by ID"}
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "Retrieves a user by ID"
    end

    test "documents request parameters" do
      manifest = build_test_manifest_with_endpoints([
        %{
          id: :search_users,
          method: :get,
          path: "/users",
          query_params: [
            {:query, :string, [required: true, description: "Search query"]},
            {:limit, :integer, [description: "Max results"]}
          ]
        }
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "| Parameter | Type | Required | Description |"
      assert docs =~ "| `query` | string | Yes | Search query |"
      assert docs =~ "| `limit` | integer | No | Max results |"
    end

    test "documents request body schema" do
      manifest = build_test_manifest_with_typed_endpoint()

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "#### Request Body"
      assert docs =~ "```json"
    end

    test "documents response schema" do
      manifest = build_test_manifest_with_typed_endpoint()

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "#### Response"
    end

    test "generates type reference section" do
      manifest = build_test_manifest_with_types([
        %{id: :user, description: "User object"}
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Type Reference"
      assert docs =~ "### User"
      assert docs =~ "User object"
    end

    test "documents type fields" do
      manifest = build_test_manifest_with_types([
        %{id: :user, schema: user_schema_with_fields()}
      ])

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "| Field | Type | Required | Description |"
      assert docs =~ "| `id` |"
      assert docs =~ "| `name` |"
    end

    test "includes authentication section" do
      manifest = build_test_manifest_with_auth(:bearer)

      {:ok, docs} = Docs.generate(manifest)

      assert docs =~ "## Authentication"
      assert docs =~ "Bearer token"
    end

    test "generates example requests" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :create_user, method: :post, path: "/users", request_type: :user_create}
      ])

      {:ok, docs} = Docs.generate(manifest, examples: true)

      assert docs =~ "#### Example Request"
      assert docs =~ "```elixir"
    end
  end

  describe "generate_html/2" do
    test "generates HTML documentation" do
      manifest = build_test_manifest()

      {:ok, html} = Docs.generate_html(manifest)

      assert html =~ "<html>"
      assert html =~ "<h1>TestAPI</h1>"
    end
  end

  # Helper functions
  defp build_test_manifest(attrs \\ %{}), do: ...
  defp build_test_manifest_with_endpoints(endpoints), do: ...
  defp build_test_manifest_with_typed_endpoint, do: ...
  defp build_test_manifest_with_types(types), do: ...
  defp build_test_manifest_with_auth(scheme), do: ...
  defp user_schema_with_fields, do: ...
end
```

### Implementation

Create `/home/home/p/g/n/pristine/lib/pristine/docs.ex`:

```elixir
defmodule Pristine.Docs do
  @moduledoc """
  Generates documentation from Pristine manifests.

  ## Usage

      {:ok, markdown} = Pristine.Docs.generate(manifest)
      {:ok, html} = Pristine.Docs.generate_html(manifest)
  """

  alias Pristine.Manifest
  alias Pristine.Manifest.{Endpoint, TypeDef}

  @type option :: {:examples, boolean()} | {:include_types, boolean()}

  @spec generate(Manifest.t(), [option]) :: {:ok, String.t()} | {:error, term()}
  def generate(%Manifest{} = manifest, opts \\ []) do
    sections = [
      generate_title(manifest),
      generate_overview(manifest),
      generate_auth_section(manifest),
      generate_toc(manifest),
      generate_endpoints_sections(manifest, opts),
      generate_types_section(manifest, opts)
    ]

    markdown = Enum.join(sections, "\n\n")
    {:ok, markdown}
  end

  @spec generate_html(Manifest.t(), [option]) :: {:ok, String.t()} | {:error, term()}
  def generate_html(%Manifest{} = manifest, opts \\ []) do
    with {:ok, markdown} <- generate(manifest, opts) do
      html = markdown_to_html(markdown, manifest)
      {:ok, html}
    end
  end

  # Private functions

  defp generate_title(%Manifest{name: name}) do
    "# #{name || "API Documentation"}"
  end

  defp generate_overview(%Manifest{} = manifest) do
    parts = ["## Overview"]

    if manifest.description do
      parts = parts ++ [manifest.description]
    end

    meta = []

    if manifest.base_url do
      meta = meta ++ ["Base URL: `#{manifest.base_url}`"]
    end

    if manifest.version do
      meta = meta ++ ["Version: #{manifest.version}"]
    end

    if Enum.any?(meta) do
      parts ++ meta
    else
      parts
    end
    |> Enum.join("\n\n")
  end

  defp generate_auth_section(%Manifest{auth: nil}), do: ""
  defp generate_auth_section(%Manifest{auth: auth}) do
    auth_desc = case auth do
      :bearer -> "This API uses Bearer token authentication. Include an `Authorization: Bearer <token>` header with all requests."
      :api_key -> "This API uses API key authentication. Include an `X-API-Key: <key>` header with all requests."
      _ -> "Authentication required."
    end

    """
    ## Authentication

    #{auth_desc}
    """
  end

  defp generate_toc(%Manifest{endpoints: endpoints}) do
    resources =
      endpoints
      |> Enum.map(& &1.resource)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(resources) do
      ""
    else
      items = Enum.map(resources, fn resource ->
        name = resource |> to_string() |> Macro.camelize()
        anchor = resource |> to_string() |> String.downcase()
        "- [#{name}](##{anchor})"
      end)

      """
      ## Table of Contents

      #{Enum.join(items, "\n")}
      """
    end
  end

  defp generate_endpoints_sections(%Manifest{endpoints: endpoints}, opts) do
    endpoints
    |> Enum.group_by(& &1.resource)
    |> Enum.map(fn {resource, group} ->
      generate_resource_section(resource, group, opts)
    end)
    |> Enum.join("\n\n")
  end

  defp generate_resource_section(resource, endpoints, opts) do
    section_title = if resource do
      "## #{resource |> to_string() |> Macro.camelize()}"
    else
      "## Endpoints"
    end

    endpoint_docs = Enum.map(endpoints, fn endpoint ->
      generate_endpoint_doc(endpoint, opts)
    end)

    [section_title | endpoint_docs]
    |> Enum.join("\n\n")
  end

  defp generate_endpoint_doc(%Endpoint{} = endpoint, opts) do
    parts = [
      "### #{method_string(endpoint.method)} #{endpoint.path}"
    ]

    if endpoint.description do
      parts = parts ++ [endpoint.description]
    end

    parts = parts ++ [
      generate_params_table(endpoint),
      generate_request_body_doc(endpoint),
      generate_response_doc(endpoint)
    ]

    if Keyword.get(opts, :examples, false) do
      parts = parts ++ [generate_example(endpoint)]
    end

    parts
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end

  defp generate_params_table(%Endpoint{query_params: nil, path: path}) do
    path_params = extract_path_params(path)
    if Enum.empty?(path_params) do
      ""
    else
      generate_path_params_table(path_params)
    end
  end

  defp generate_params_table(%Endpoint{} = endpoint) do
    path_params = extract_path_params(endpoint.path)
    query_params = endpoint.query_params || []

    all_params =
      build_path_param_rows(path_params) ++
      build_query_param_rows(query_params)

    if Enum.empty?(all_params) do
      ""
    else
      header = "| Parameter | Type | Required | Description |\n|-----------|------|----------|-------------|"
      rows = Enum.map(all_params, fn {name, type, required, desc} ->
        req = if required, do: "Yes", else: "No"
        "| `#{name}` | #{type} | #{req} | #{desc || ""} |"
      end)

      """
      #### Parameters

      #{header}
      #{Enum.join(rows, "\n")}
      """
    end
  end

  defp extract_path_params(path) do
    ~r/\{([^}]+)\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp build_path_param_rows(params) do
    Enum.map(params, fn name -> {name, "string", true, "Path parameter"} end)
  end

  defp build_query_param_rows(params) do
    Enum.map(params, fn {name, type, opts} ->
      {to_string(name), type_string(type), Keyword.get(opts, :required, false), Keyword.get(opts, :description)}
    end)
  end

  defp generate_path_params_table(params) do
    header = "| Parameter | Type | Required | Description |\n|-----------|------|----------|-------------|"
    rows = Enum.map(params, fn name ->
      "| `#{name}` | string | Yes | Path parameter |"
    end)

    """
    #### Parameters

    #{header}
    #{Enum.join(rows, "\n")}
    """
  end

  defp generate_request_body_doc(%Endpoint{request_type: nil}), do: ""
  defp generate_request_body_doc(%Endpoint{request_type: type}) do
    """
    #### Request Body

    Type: [`#{type_name(type)}`](##{type_anchor(type)})

    ```json
    #{generate_example_json(type)}
    ```
    """
  end

  defp generate_response_doc(%Endpoint{response_type: nil}), do: ""
  defp generate_response_doc(%Endpoint{response_type: type}) do
    """
    #### Response

    Type: [`#{type_name(type)}`](##{type_anchor(type)})
    """
  end

  defp generate_example(%Endpoint{} = endpoint) do
    module_name = endpoint.id |> to_string() |> Macro.camelize()

    """
    #### Example Request

    ```elixir
    client = MyAPI.Client.new(api_key: "your-api-key")
    {:ok, response} = MyAPI.#{module_name}.call(client, params)
    ```
    """
  end

  defp generate_types_section(%Manifest{types: []}, _opts), do: ""
  defp generate_types_section(%Manifest{types: types}, _opts) do
    type_docs = Enum.map(types, &generate_type_doc/1)

    """
    ## Type Reference

    #{Enum.join(type_docs, "\n\n")}
    """
  end

  defp generate_type_doc(%TypeDef{id: id, description: desc, schema: schema}) do
    parts = ["### #{type_name(id)}"]

    if desc do
      parts = parts ++ [desc]
    end

    if schema && schema[:properties] do
      parts = parts ++ [generate_fields_table(schema[:properties])]
    end

    Enum.join(parts, "\n\n")
  end

  defp generate_fields_table(properties) do
    header = "| Field | Type | Required | Description |\n|-------|------|----------|-------------|"
    rows = Enum.map(properties, fn {name, type, opts} ->
      req = if Keyword.get(opts, :required, false), do: "Yes", else: "No"
      desc = Keyword.get(opts, :description, "")
      "| `#{name}` | #{type_string(type)} | #{req} | #{desc} |"
    end)

    "#{header}\n#{Enum.join(rows, "\n")}"
  end

  defp generate_example_json(_type) do
    # Placeholder - would generate from schema
    "{}"
  end

  defp markdown_to_html(markdown, manifest) do
    # Simple markdown to HTML conversion
    title = manifest.name || "API Documentation"

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{title}</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 900px; margin: 0 auto; padding: 20px; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; }
        pre { background: #f5f5f5; padding: 16px; overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
      </style>
    </head>
    <body>
    #{convert_markdown_to_html(markdown)}
    </body>
    </html>
    """
  end

  defp convert_markdown_to_html(markdown) do
    markdown
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/```(\w+)?\n(.*?)```/s, "<pre><code>\\2</code></pre>")
  end

  defp method_string(:get), do: "GET"
  defp method_string(:post), do: "POST"
  defp method_string(:put), do: "PUT"
  defp method_string(:patch), do: "PATCH"
  defp method_string(:delete), do: "DELETE"

  defp type_string(:string), do: "string"
  defp type_string(:integer), do: "integer"
  defp type_string(:number), do: "number"
  defp type_string(:boolean), do: "boolean"
  defp type_string({:array, t}), do: "array[#{type_string(t)}]"
  defp type_string(t) when is_atom(t), do: type_name(t)

  defp type_name(id), do: id |> to_string() |> Macro.camelize()
  defp type_anchor(id), do: id |> to_string() |> String.downcase()
end
```

Create `/home/home/p/g/n/pristine/lib/mix/tasks/pristine.docs.ex`:

```elixir
defmodule Mix.Tasks.Pristine.Docs do
  @moduledoc """
  Generates documentation from a Pristine manifest.

  ## Usage

      mix pristine.docs --manifest path/to/manifest.json
      mix pristine.docs --manifest path/to/manifest.json --output docs/api.md
      mix pristine.docs --manifest path/to/manifest.json --format html --output docs/api.html

  ## Options

    * `--manifest` - Path to the Pristine manifest file (required)
    * `--output` - Output file path (default: stdout)
    * `--format` - Output format: markdown or html (default: markdown)
    * `--examples` - Include example requests (default: false)
  """

  use Mix.Task

  @shortdoc "Generate documentation from manifest"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [
      manifest: :string,
      output: :string,
      format: :string,
      examples: :boolean
    ])

    manifest_path = opts[:manifest] || raise_missing_manifest()
    output_path = opts[:output]
    format = parse_format(opts[:format])
    doc_opts = [examples: Keyword.get(opts, :examples, false)]

    manifest = load_manifest!(manifest_path)

    result = case format do
      :markdown -> Pristine.Docs.generate(manifest, doc_opts)
      :html -> Pristine.Docs.generate_html(manifest, doc_opts)
    end

    case result do
      {:ok, docs} ->
        output_docs(docs, output_path)
      {:error, reason} ->
        Mix.raise("Failed to generate docs: #{inspect(reason)}")
    end
  end

  defp load_manifest!(path) do
    case Pristine.Manifest.load_file(path) do
      {:ok, manifest} -> manifest
      {:error, reason} -> Mix.raise("Failed to load manifest: #{inspect(reason)}")
    end
  end

  defp parse_format(nil), do: :markdown
  defp parse_format("markdown"), do: :markdown
  defp parse_format("md"), do: :markdown
  defp parse_format("html"), do: :html
  defp parse_format(other), do: Mix.raise("Unknown format: #{other}")

  defp output_docs(docs, nil), do: Mix.shell().info(docs)
  defp output_docs(docs, path) do
    File.write!(path, docs)
    Mix.shell().info("Documentation written to #{path}")
  end

  defp raise_missing_manifest do
    Mix.raise("--manifest option is required")
  end
end
```

---

## Task 5.3: Test Fixtures Module

### Context

Provide utilities for generating test fixtures from manifest type definitions, enabling easy testing of generated clients.

### Files to Create

- `/home/home/p/g/n/pristine/lib/pristine/test/fixtures.ex`
- `/home/home/p/g/n/pristine/test/pristine/test/fixtures_test.exs`

### Tests First

Create `/home/home/p/g/n/pristine/test/pristine/test/fixtures_test.exs`:

```elixir
defmodule Pristine.Test.FixturesTest do
  use ExUnit.Case, async: true

  alias Pristine.Test.Fixtures

  describe "generate/2" do
    test "generates fixture for string type" do
      schema = %{type: :string}

      fixture = Fixtures.generate(schema)

      assert is_binary(fixture)
    end

    test "generates fixture with string constraints" do
      schema = %{type: :string, min_length: 5, max_length: 10}

      fixture = Fixtures.generate(schema)

      assert String.length(fixture) >= 5
      assert String.length(fixture) <= 10
    end

    test "generates fixture for integer type" do
      schema = %{type: :integer}

      fixture = Fixtures.generate(schema)

      assert is_integer(fixture)
    end

    test "generates fixture with integer constraints" do
      schema = %{type: :integer, minimum: 1, maximum: 100}

      fixture = Fixtures.generate(schema)

      assert fixture >= 1
      assert fixture <= 100
    end

    test "generates fixture for boolean type" do
      schema = %{type: :boolean}

      fixture = Fixtures.generate(schema)

      assert is_boolean(fixture)
    end

    test "generates fixture for array type" do
      schema = %{type: {:array, :string}}

      fixture = Fixtures.generate(schema)

      assert is_list(fixture)
      assert Enum.all?(fixture, &is_binary/1)
    end

    test "generates fixture with array length constraints" do
      schema = %{type: {:array, :integer}, min_items: 2, max_items: 5}

      fixture = Fixtures.generate(schema)

      assert length(fixture) >= 2
      assert length(fixture) <= 5
    end

    test "generates fixture for map type with properties" do
      schema = %{
        type: :map,
        properties: [
          {:name, :string, [required: true]},
          {:age, :integer, []}
        ]
      }

      fixture = Fixtures.generate(schema)

      assert is_map(fixture)
      assert is_binary(fixture["name"])
      assert is_integer(fixture["age"]) or is_nil(fixture["age"])
    end

    test "includes all required fields" do
      schema = %{
        type: :map,
        properties: [
          {:id, :string, [required: true]},
          {:name, :string, [required: true]},
          {:optional, :string, []}
        ]
      }

      fixture = Fixtures.generate(schema)

      assert Map.has_key?(fixture, "id")
      assert Map.has_key?(fixture, "name")
    end

    test "generates fixture for literal type" do
      schema = %{type: {:literal, "constant"}}

      fixture = Fixtures.generate(schema)

      assert fixture == "constant"
    end

    test "generates fixture for union type" do
      schema = %{type: {:union, [:string, :integer]}}

      fixture = Fixtures.generate(schema)

      assert is_binary(fixture) or is_integer(fixture)
    end

    test "generates fixture for discriminated union" do
      schema = %{
        type: {:discriminated_union, [
          discriminator: "type",
          variants: %{
            "text" => %{type: :map, properties: [{:text, :string, [required: true]}]},
            "image" => %{type: :map, properties: [{:url, :string, [required: true]}]}
          }
        ]}
      }

      fixture = Fixtures.generate(schema)

      assert fixture["type"] in ["text", "image"]
    end

    test "respects seed option for reproducibility" do
      schema = %{type: :integer}

      fixture1 = Fixtures.generate(schema, seed: 12345)
      fixture2 = Fixtures.generate(schema, seed: 12345)

      assert fixture1 == fixture2
    end

    test "generates different fixtures without seed" do
      schema = %{type: :string, min_length: 20}

      fixtures = for _ <- 1..10, do: Fixtures.generate(schema)
      unique = Enum.uniq(fixtures)

      # Should have some variation
      assert length(unique) > 1
    end
  end

  describe "generate_list/3" do
    test "generates list of fixtures" do
      schema = %{type: :string}

      fixtures = Fixtures.generate_list(schema, 5)

      assert length(fixtures) == 5
      assert Enum.all?(fixtures, &is_binary/1)
    end
  end

  describe "for_manifest/2" do
    test "generates fixtures for all types in manifest" do
      manifest = build_test_manifest_with_types([
        %{id: :user, schema: user_schema()},
        %{id: :post, schema: post_schema()}
      ])

      fixtures = Fixtures.for_manifest(manifest)

      assert Map.has_key?(fixtures, :user)
      assert Map.has_key?(fixtures, :post)
    end
  end

  describe "for_endpoint/2" do
    test "generates request and response fixtures for endpoint" do
      manifest = build_test_manifest_with_typed_endpoint()
      endpoint = Enum.find(manifest.endpoints, & &1.id == :create_user)

      fixtures = Fixtures.for_endpoint(manifest, endpoint)

      assert Map.has_key?(fixtures, :request)
      assert Map.has_key?(fixtures, :response)
    end
  end

  # Helpers
  defp build_test_manifest_with_types(types), do: ...
  defp build_test_manifest_with_typed_endpoint, do: ...
  defp user_schema, do: ...
  defp post_schema, do: ...
end
```

### Implementation

Create `/home/home/p/g/n/pristine/lib/pristine/test/fixtures.ex`:

```elixir
defmodule Pristine.Test.Fixtures do
  @moduledoc """
  Generates test fixtures from Pristine manifest type definitions.

  ## Usage

      # Generate a single fixture
      fixture = Fixtures.generate(schema)

      # Generate with seed for reproducibility
      fixture = Fixtures.generate(schema, seed: 12345)

      # Generate list of fixtures
      fixtures = Fixtures.generate_list(schema, 10)

      # Generate fixtures for all manifest types
      fixtures = Fixtures.for_manifest(manifest)
  """

  alias Pristine.Manifest
  alias Pristine.Manifest.{Endpoint, TypeDef}

  @type option :: {:seed, integer()} | {:include_optional, boolean()}

  @spec generate(map(), [option]) :: term()
  def generate(schema, opts \\ []) do
    state = init_state(opts)
    {value, _state} = do_generate(schema, state)
    value
  end

  @spec generate_list(map(), pos_integer(), [option]) :: [term()]
  def generate_list(schema, count, opts \\ []) do
    state = init_state(opts)

    {fixtures, _state} =
      Enum.reduce(1..count, {[], state}, fn _, {acc, s} ->
        {value, new_state} = do_generate(schema, s)
        {[value | acc], new_state}
      end)

    Enum.reverse(fixtures)
  end

  @spec for_manifest(Manifest.t(), [option]) :: %{atom() => term()}
  def for_manifest(%Manifest{types: types}, opts \\ []) do
    state = init_state(opts)

    {fixtures, _state} =
      Enum.reduce(types, {%{}, state}, fn %TypeDef{id: id, schema: schema}, {acc, s} ->
        {value, new_state} = do_generate(schema, s)
        {Map.put(acc, id, value), new_state}
      end)

    fixtures
  end

  @spec for_endpoint(Manifest.t(), Endpoint.t(), [option]) :: %{atom() => term()}
  def for_endpoint(%Manifest{} = manifest, %Endpoint{} = endpoint, opts \\ []) do
    state = init_state(opts)

    {request_fixture, state} =
      if endpoint.request_type do
        type_def = find_type(manifest, endpoint.request_type)
        do_generate(type_def.schema, state)
      else
        {nil, state}
      end

    {response_fixture, _state} =
      if endpoint.response_type do
        type_def = find_type(manifest, endpoint.response_type)
        do_generate(type_def.schema, state)
      else
        {nil, state}
      end

    %{request: request_fixture, response: response_fixture}
  end

  # Private functions

  defp init_state(opts) do
    seed = Keyword.get(opts, :seed)
    include_optional = Keyword.get(opts, :include_optional, true)

    rng = if seed, do: :rand.seed(:exsss, {seed, seed, seed}), else: :rand.seed(:exsss)

    %{
      rng: rng,
      include_optional: include_optional
    }
  end

  defp do_generate(%{type: :string} = schema, state) do
    min_len = Map.get(schema, :min_length, 5)
    max_len = Map.get(schema, :max_length, 20)

    {length, state} = random_int(min_len, max_len, state)
    {random_string(length, state), state}
  end

  defp do_generate(%{type: :integer} = schema, state) do
    min = Map.get(schema, :minimum, 1)
    max = Map.get(schema, :maximum, 1000)
    random_int(min, max, state)
  end

  defp do_generate(%{type: :number} = schema, state) do
    min = Map.get(schema, :minimum, 0.0)
    max = Map.get(schema, :maximum, 1000.0)
    random_float(min, max, state)
  end

  defp do_generate(%{type: :boolean}, state) do
    {n, state} = random_int(0, 1, state)
    {n == 1, state}
  end

  defp do_generate(%{type: {:array, item_type}} = schema, state) do
    min_items = Map.get(schema, :min_items, 1)
    max_items = Map.get(schema, :max_items, 5)

    {count, state} = random_int(min_items, max_items, state)

    {items, state} =
      Enum.reduce(1..count, {[], state}, fn _, {acc, s} ->
        {item, new_state} = do_generate(%{type: item_type}, s)
        {[item | acc], new_state}
      end)

    {Enum.reverse(items), state}
  end

  defp do_generate(%{type: {:literal, value}}, state) do
    {value, state}
  end

  defp do_generate(%{type: {:union, types}}, state) do
    {index, state} = random_int(0, length(types) - 1, state)
    type = Enum.at(types, index)
    do_generate(%{type: type}, state)
  end

  defp do_generate(%{type: {:discriminated_union, opts}}, state) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    keys = Map.keys(variants)
    {index, state} = random_int(0, length(keys) - 1, state)
    selected_key = Enum.at(keys, index)
    variant_schema = Map.fetch!(variants, selected_key)

    {value, state} = do_generate(variant_schema, state)
    {Map.put(value, discriminator, selected_key), state}
  end

  defp do_generate(%{type: :map, properties: props}, state) do
    {map, state} =
      Enum.reduce(props, {%{}, state}, fn {name, type, opts}, {acc, s} ->
        required = Keyword.get(opts, :required, false)

        if required or s.include_optional do
          {value, new_state} = do_generate(%{type: type}, s)
          {Map.put(acc, to_string(name), value), new_state}
        else
          {acc, s}
        end
      end)

    {map, state}
  end

  defp do_generate(%{type: type_ref}, state) when is_atom(type_ref) do
    # Type reference - generate placeholder
    {%{"_type" => to_string(type_ref)}, state}
  end

  defp random_int(min, max, state) when min == max, do: {min, state}
  defp random_int(min, max, state) do
    {n, _} = :rand.uniform_s(max - min + 1, state.rng)
    {n + min - 1, %{state | rng: elem(:rand.uniform_s(state.rng), 1)}}
  end

  defp random_float(min, max, state) do
    {n, _} = :rand.uniform_s(state.rng)
    value = min + n * (max - min)
    {value, %{state | rng: elem(:rand.uniform_s(state.rng), 1)}}
  end

  defp random_string(length, state) do
    chars = ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    {chars_list, _state} =
      Enum.reduce(1..length, {[], state}, fn _, {acc, s} ->
        {idx, new_state} = random_int(0, length(chars) - 1, s)
        char = Enum.at(chars, idx)
        {[char | acc], new_state}
      end)

    to_string(Enum.reverse(chars_list))
  end

  defp find_type(%Manifest{types: types}, type_id) do
    Enum.find(types, & &1.id == type_id) ||
      raise "Type not found: #{type_id}"
  end
end
```

---

## Task 5.4: Mock Server Generation

### Context

Generate mock servers that respond according to manifest definitions, enabling integration testing without real API calls.

### Files to Create

- `/home/home/p/g/n/pristine/lib/pristine/test/mock_server.ex`
- `/home/home/p/g/n/pristine/test/pristine/test/mock_server_test.exs`

### Tests First

Create `/home/home/p/g/n/pristine/test/pristine/test/mock_server_test.exs`:

```elixir
defmodule Pristine.Test.MockServerTest do
  use ExUnit.Case, async: true

  alias Pristine.Test.MockServer

  describe "start/2" do
    test "starts a mock server on specified port" do
      manifest = build_test_manifest()

      {:ok, server} = MockServer.start(manifest, port: 0)

      assert is_pid(server.pid)
      assert is_integer(server.port)

      MockServer.stop(server)
    end

    test "server responds to GET requests" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}", response_type: :user}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      {:ok, response} = Finch.build(:get, "http://localhost:#{server.port}/users/123")
                        |> Finch.request(TestFinch)

      assert response.status == 200
      assert {:ok, _body} = Jason.decode(response.body)

      MockServer.stop(server)
    end

    test "server responds to POST requests with body" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :create_user, method: :post, path: "/users", request_type: :user_create}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      body = Jason.encode!(%{name: "Test"})
      {:ok, response} = Finch.build(:post, "http://localhost:#{server.port}/users", [], body)
                        |> Finch.request(TestFinch)

      assert response.status == 201

      MockServer.stop(server)
    end

    test "server returns 404 for unknown endpoints" do
      manifest = build_test_manifest()

      {:ok, server} = MockServer.start(manifest, port: 0)

      {:ok, response} = Finch.build(:get, "http://localhost:#{server.port}/unknown")
                        |> Finch.request(TestFinch)

      assert response.status == 404

      MockServer.stop(server)
    end

    test "server validates request body against schema" do
      manifest = build_test_manifest_with_typed_endpoint()

      {:ok, server} = MockServer.start(manifest, port: 0, validate: true)

      # Invalid body
      body = Jason.encode!(%{})
      {:ok, response} = Finch.build(:post, "http://localhost:#{server.port}/users", [], body)
                        |> Finch.request(TestFinch)

      assert response.status == 400

      MockServer.stop(server)
    end

    test "server supports custom response handlers" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      handler = fn _request ->
        {:ok, %{status: 200, body: %{custom: true}}}
      end

      {:ok, server} = MockServer.start(manifest,
        port: 0,
        handlers: %{get_user: handler}
      )

      {:ok, response} = Finch.build(:get, "http://localhost:#{server.port}/users/123")
                        |> Finch.request(TestFinch)

      assert response.status == 200
      body = Jason.decode!(response.body)
      assert body["custom"] == true

      MockServer.stop(server)
    end
  end

  describe "expect/3" do
    test "sets expected responses" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, :get_user, %{
        status: 200,
        body: %{id: "123", name: "Expected User"}
      })

      {:ok, response} = Finch.build(:get, "http://localhost:#{server.port}/users/123")
                        |> Finch.request(TestFinch)

      body = Jason.decode!(response.body)
      assert body["name"] == "Expected User"

      MockServer.stop(server)
    end

    test "expectations are consumed in order" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, :get_user, %{body: %{name: "First"}})
      MockServer.expect(server, :get_user, %{body: %{name: "Second"}})

      {:ok, r1} = Finch.build(:get, "http://localhost:#{server.port}/users/1")
                  |> Finch.request(TestFinch)
      {:ok, r2} = Finch.build(:get, "http://localhost:#{server.port}/users/2")
                  |> Finch.request(TestFinch)

      assert Jason.decode!(r1.body)["name"] == "First"
      assert Jason.decode!(r2.body)["name"] == "Second"

      MockServer.stop(server)
    end
  end

  describe "verify!/1" do
    test "raises if expected calls were not made" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, :get_user, %{body: %{}})

      assert_raise RuntimeError, ~r/unfulfilled expectation/, fn ->
        MockServer.verify!(server)
      end

      MockServer.stop(server)
    end

    test "succeeds when all expectations fulfilled" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      MockServer.expect(server, :get_user, %{body: %{}})

      Finch.build(:get, "http://localhost:#{server.port}/users/123")
      |> Finch.request(TestFinch)

      assert :ok = MockServer.verify!(server)

      MockServer.stop(server)
    end
  end

  describe "history/1" do
    test "returns list of received requests" do
      manifest = build_test_manifest_with_endpoints([
        %{id: :get_user, method: :get, path: "/users/{id}"}
      ])

      {:ok, server} = MockServer.start(manifest, port: 0)

      Finch.build(:get, "http://localhost:#{server.port}/users/123")
      |> Finch.request(TestFinch)

      Finch.build(:get, "http://localhost:#{server.port}/users/456")
      |> Finch.request(TestFinch)

      history = MockServer.history(server)

      assert length(history) == 2
      assert Enum.at(history, 0).path_params["id"] == "123"
      assert Enum.at(history, 1).path_params["id"] == "456"

      MockServer.stop(server)
    end
  end

  # Helpers
  defp build_test_manifest, do: ...
  defp build_test_manifest_with_endpoints(endpoints), do: ...
  defp build_test_manifest_with_typed_endpoint, do: ...
end
```

### Implementation

Create `/home/home/p/g/n/pristine/lib/pristine/test/mock_server.ex`:

```elixir
defmodule Pristine.Test.MockServer do
  @moduledoc """
  Mock HTTP server for testing Pristine-generated clients.

  ## Usage

      # Start server
      {:ok, server} = MockServer.start(manifest, port: 4001)

      # Set expectations
      MockServer.expect(server, :get_user, %{
        status: 200,
        body: %{id: "123", name: "Test User"}
      })

      # Make requests to http://localhost:4001/...

      # Verify expectations
      MockServer.verify!(server)

      # Stop server
      MockServer.stop(server)
  """

  use GenServer

  alias Pristine.Manifest
  alias Pristine.Manifest.Endpoint
  alias Pristine.Test.Fixtures

  defstruct [:pid, :port, :manifest, :ref]

  @type t :: %__MODULE__{
    pid: pid(),
    port: non_neg_integer(),
    manifest: Manifest.t(),
    ref: reference()
  }

  @type option ::
    {:port, non_neg_integer()}
    | {:validate, boolean()}
    | {:handlers, %{atom() => function()}}

  @spec start(Manifest.t(), [option]) :: {:ok, t()} | {:error, term()}
  def start(%Manifest{} = manifest, opts \\ []) do
    port = Keyword.get(opts, :port, 0)
    validate = Keyword.get(opts, :validate, false)
    handlers = Keyword.get(opts, :handlers, %{})

    state = %{
      manifest: manifest,
      validate: validate,
      handlers: handlers,
      expectations: %{},
      history: []
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, state)

    # Start Plug/Bandit server
    ref = make_ref()
    plug_opts = [manifest: manifest, server_pid: pid]

    {:ok, _} = Bandit.start_link(
      plug: {__MODULE__.Router, plug_opts},
      port: port,
      ref: ref
    )

    actual_port = get_port(ref)

    {:ok, %__MODULE__{
      pid: pid,
      port: actual_port,
      manifest: manifest,
      ref: ref
    }}
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{ref: ref}) do
    Bandit.stop(ref)
    :ok
  end

  @spec expect(t(), atom(), map()) :: :ok
  def expect(%__MODULE__{pid: pid}, endpoint_id, response) do
    GenServer.call(pid, {:expect, endpoint_id, response})
  end

  @spec verify!(t()) :: :ok
  def verify!(%__MODULE__{pid: pid}) do
    case GenServer.call(pid, :verify) do
      :ok -> :ok
      {:error, unfulfilled} ->
        raise "MockServer has unfulfilled expectation for: #{inspect(unfulfilled)}"
    end
  end

  @spec history(t()) :: [map()]
  def history(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :history)
  end

  # GenServer callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:expect, endpoint_id, response}, _from, state) do
    expectations = Map.update(
      state.expectations,
      endpoint_id,
      [response],
      &(&1 ++ [response])
    )
    {:reply, :ok, %{state | expectations: expectations}}
  end

  def handle_call(:verify, _from, state) do
    unfulfilled =
      state.expectations
      |> Enum.filter(fn {_id, responses} -> responses != [] end)
      |> Enum.map(fn {id, _} -> id end)

    result = if Enum.empty?(unfulfilled), do: :ok, else: {:error, unfulfilled}
    {:reply, result, state}
  end

  def handle_call(:history, _from, state) do
    {:reply, Enum.reverse(state.history), state}
  end

  def handle_call({:handle_request, request}, _from, state) do
    {response, state} = process_request(request, state)
    state = %{state | history: [request | state.history]}
    {:reply, response, state}
  end

  # Private

  defp process_request(request, state) do
    endpoint_id = request.endpoint_id

    cond do
      # Check for custom handler
      handler = Map.get(state.handlers, endpoint_id) ->
        response = handler.(request)
        {response, state}

      # Check for expectation
      [expected | rest] = Map.get(state.expectations, endpoint_id, [nil]) ->
        if expected do
          expectations = Map.put(state.expectations, endpoint_id, rest)
          {{:ok, normalize_response(expected)}, %{state | expectations: expectations}}
        else
          # Generate fixture response
          response = generate_response(state.manifest, endpoint_id)
          {{:ok, response}, state}
        end

      true ->
        response = generate_response(state.manifest, endpoint_id)
        {{:ok, response}, state}
    end
  end

  defp generate_response(manifest, endpoint_id) do
    endpoint = find_endpoint(manifest, endpoint_id)

    body = if endpoint && endpoint.response_type do
      type_def = find_type(manifest, endpoint.response_type)
      if type_def, do: Fixtures.generate(type_def.schema), else: %{}
    else
      %{}
    end

    status = if endpoint && endpoint.method == :post, do: 201, else: 200

    %{status: status, body: body, headers: []}
  end

  defp normalize_response(%{status: status} = resp) do
    %{
      status: status,
      body: Map.get(resp, :body, %{}),
      headers: Map.get(resp, :headers, [])
    }
  end
  defp normalize_response(%{body: body}) do
    %{status: 200, body: body, headers: []}
  end

  defp find_endpoint(%Manifest{endpoints: endpoints}, id) do
    Enum.find(endpoints, & &1.id == id)
  end

  defp find_type(%Manifest{types: types}, id) do
    Enum.find(types, & &1.id == id)
  end

  defp get_port(ref) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(ref)
    port
  end

  # Router module
  defmodule Router do
    use Plug.Router

    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug :dispatch

    match _ do
      manifest = conn.private[:manifest]
      server_pid = conn.private[:server_pid]

      {endpoint, path_params} = match_endpoint(manifest, conn.method, conn.request_path)

      if endpoint do
        request = %{
          endpoint_id: endpoint.id,
          method: conn.method,
          path: conn.request_path,
          path_params: path_params,
          query_params: conn.query_params,
          body: conn.body_params,
          headers: conn.req_headers
        }

        case GenServer.call(server_pid, {:handle_request, request}) do
          {:ok, response} ->
            body = if is_map(response.body), do: Jason.encode!(response.body), else: response.body

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(response.status, body)

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
        end
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Not found"}))
      end
    end

    defp match_endpoint(%Manifest{endpoints: endpoints}, method, path) do
      method_atom = method |> String.downcase() |> String.to_atom()

      Enum.find_value(endpoints, fn endpoint ->
        if endpoint.method == method_atom do
          case match_path(endpoint.path, path) do
            {:ok, params} -> {endpoint, params}
            :nomatch -> nil
          end
        end
      end) || {nil, %{}}
    end

    defp match_path(template, actual) do
      template_parts = String.split(template, "/")
      actual_parts = String.split(actual, "/")

      if length(template_parts) == length(actual_parts) do
        match_parts(template_parts, actual_parts, %{})
      else
        :nomatch
      end
    end

    defp match_parts([], [], params), do: {:ok, params}
    defp match_parts(["{" <> rest | t_rest], [value | a_rest], params) do
      param_name = String.trim_trailing(rest, "}")
      match_parts(t_rest, a_rest, Map.put(params, param_name, value))
    end
    defp match_parts([same | t_rest], [same | a_rest], params) do
      match_parts(t_rest, a_rest, params)
    end
    defp match_parts(_, _, _), do: :nomatch
  end
end
```

---

## Verification Checklist

After completing all tasks, verify:

### Tests
```bash
cd /home/home/p/g/n/pristine
mix test test/pristine/openapi_test.exs
mix test test/pristine/docs_test.exs
mix test test/pristine/test/fixtures_test.exs
mix test test/pristine/test/mock_server_test.exs
mix test test/mix/tasks/pristine_openapi_test.exs
mix test test/mix/tasks/pristine_docs_test.exs
```

### No Warnings
```bash
mix compile --warnings-as-errors
```

### Dialyzer
```bash
mix dialyzer
```

### Credo
```bash
mix credo --strict
```

### Integration Test
```bash
# Create test manifest
cat > /tmp/test_manifest.json << 'EOF'
{
  "name": "TestAPI",
  "version": "1.0.0",
  "base_url": "https://api.example.com",
  "endpoints": [
    {"id": "get_user", "method": "get", "path": "/users/{id}"}
  ],
  "types": []
}
EOF

# Test OpenAPI generation
mix pristine.openapi --manifest /tmp/test_manifest.json

# Test docs generation
mix pristine.docs --manifest /tmp/test_manifest.json
```

---

## Dependencies to Add

Add to `/home/home/p/g/n/pristine/mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps ...
    {:bandit, "~> 1.0", only: :test},
    {:plug, "~> 1.14"},
    {:finch, "~> 0.16", only: :test}
  ]
end
```

---

## Success Criteria

1. `mix pristine.openapi --manifest manifest.json` generates valid OpenAPI 3.1 spec
2. `mix pristine.docs --manifest manifest.json` generates readable markdown documentation
3. `Pristine.Test.Fixtures` generates valid test data from schemas
4. `Pristine.Test.MockServer` runs mock server matching manifest endpoints
5. All tests pass
6. No compiler warnings
7. Dialyzer passes
8. Credo strict passes
