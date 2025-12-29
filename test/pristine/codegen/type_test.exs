defmodule Pristine.Codegen.TypeTest do
  use ExUnit.Case, async: true

  alias Pristine.Codegen.Type

  describe "render_type_module/3" do
    test "generates module with Sinter schema" do
      type_def = %{
        "fields" => [
          %{"name" => "prompt", "type" => "string", "required" => true},
          %{"name" => "max_tokens", "type" => "integer", "required" => false}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.SampleRequest", "SampleRequest", type_def)

      assert code =~ "defmodule MyAPI.Types.SampleRequest do"
      assert code =~ "@moduledoc"
      assert code =~ "defstruct"
      assert code =~ ":prompt"
      assert code =~ ":max_tokens"
      assert code =~ "def schema do"
      assert code =~ "Sinter.Schema.define"
    end

    test "generates @type t specification" do
      type_def = %{
        "fields" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.User", "User", type_def)

      assert code =~ "@type t :: %__MODULE__{"
      assert code =~ "name: String.t()"
    end

    test "generates from_map/1 and to_map/1 functions" do
      type_def = %{"fields" => []}

      code = Type.render_type_module("MyAPI.Types.Empty", "Empty", type_def)

      assert code =~ "def from_map(data)"
      assert code =~ "def to_map(%__MODULE__{} = struct)"
    end

    test "generates new/1 constructor" do
      type_def = %{"fields" => []}

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "def new(attrs \\\\ [])"
    end

    test "generates schema fields with correct types" do
      type_def = %{
        "fields" => [
          %{"name" => "name", "type" => "string", "required" => true},
          %{"name" => "count", "type" => "integer", "required" => false}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "{:name, :string, [required: true]}"
      assert code =~ "{:count, :integer, [optional: true]}"
    end

    test "handles array types" do
      type_def = %{
        "fields" => [
          %{"name" => "items", "type" => "array", "items" => "string", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "items: [String.t()]"
      assert code =~ "{:items, {:array, :string}"
    end

    test "handles optional fields with nil type" do
      type_def = %{
        "fields" => [
          %{"name" => "optional_field", "type" => "string", "required" => false}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "optional_field: String.t() | nil"
    end

    test "includes description in moduledoc when present" do
      type_def = %{
        "description" => "A sample request for testing.",
        "fields" => []
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "A sample request for testing."
    end

    test "handles boolean type" do
      type_def = %{
        "fields" => [
          %{"name" => "enabled", "type" => "boolean", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "enabled: boolean()"
      assert code =~ "{:enabled, :boolean, [required: true]}"
    end

    test "handles float type" do
      type_def = %{
        "fields" => [
          %{"name" => "temperature", "type" => "float", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "temperature: float()"
      assert code =~ "{:temperature, :float, [required: true]}"
    end

    test "handles map type" do
      type_def = %{
        "fields" => [
          %{"name" => "metadata", "type" => "map", "required" => false}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.Test", "Test", type_def)

      assert code =~ "metadata: map() | nil"
      assert code =~ "{:metadata, :map, [optional: true]}"
    end

    test "renders literal fields with literal schema" do
      type_def = %{
        "fields" => [
          %{"name" => "type", "type" => "literal", "value" => "text", "required" => true}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.TextChunk", "TextChunk", type_def)

      assert code =~ "{:type, {:literal, \"text\"}"
    end

    test "renders choices constraints in schema options" do
      type_def = %{
        "fields" => [
          %{"name" => "format", "type" => "string", "choices" => ["png", "jpeg"]}
        ]
      }

      code = Type.render_type_module("MyAPI.Types.ImageChunk", "ImageChunk", type_def)

      assert code =~ "choices: [\"png\", \"jpeg\"]"
    end

    test "renders type refs in schema and typespecs" do
      types = %{
        "Child" => %{"fields" => [%{"name" => "name", "type" => "string"}]},
        "Parent" => %{"fields" => [%{"name" => "child", "type_ref" => "Child"}]}
      }

      code =
        Type.render_type_module("MyAPI.Types.Parent", "Parent", types["Parent"], types)

      assert code =~ "child: MyAPI.Types.Child.t()"
      assert code =~ "{:child, {:object, MyAPI.Types.Child.schema()}"
    end

    test "renders discriminated union modules" do
      type_def = %{
        "kind" => "union",
        "discriminator" => %{
          "field" => "type",
          "mapping" => %{"text" => "TextChunk", "image" => "ImageChunk"}
        }
      }

      code = Type.render_type_module("MyAPI.Types.ModelInputChunk", "ModelInputChunk", type_def)

      assert code =~ "{:discriminated_union"
      assert code =~ "\"text\" -> MyAPI.Types.TextChunk.decode"
      assert code =~ "\"image\" -> MyAPI.Types.ImageChunk.decode"
    end

    test "generated decode returns nested structs for type refs" do
      unique = System.unique_integer([:positive])
      child_name = "Child#{unique}"
      parent_name = "Parent#{unique}"

      types = %{
        child_name => %{"fields" => [%{"name" => "name", "type" => "string", "required" => true}]},
        parent_name => %{
          "fields" => [%{"name" => "child", "type_ref" => child_name, "required" => true}]
        }
      }

      child_module = "MyAPI.Types.#{child_name}"
      parent_module = "MyAPI.Types.#{parent_name}"

      Code.compile_string(
        Type.render_type_module(child_module, child_name, types[child_name], types)
      )

      Code.compile_string(
        Type.render_type_module(parent_module, parent_name, types[parent_name], types)
      )

      child_mod = Module.concat([MyAPI, Types, String.to_atom(child_name)])
      parent_mod = Module.concat([MyAPI, Types, String.to_atom(parent_name)])

      assert {:ok, parent} = parent_mod.decode(%{"child" => %{"name" => "Ada"}})
      assert %^parent_mod{} = parent
      assert %^child_mod{} = parent.child
      assert parent.child.name == "Ada"
    end
  end

  describe "render_all_type_modules/2" do
    test "generates module for each type" do
      types = %{
        "SampleRequest" => %{"fields" => []},
        "SampleResponse" => %{"fields" => []}
      }

      modules = Type.render_all_type_modules("MyAPI.Types", types)

      assert Map.has_key?(modules, "MyAPI.Types.SampleRequest")
      assert Map.has_key?(modules, "MyAPI.Types.SampleResponse")
    end

    test "returns empty map for empty types" do
      assert Type.render_all_type_modules("MyAPI.Types", %{}) == %{}
    end
  end

  describe "map_type_to_typespec/1" do
    test "maps basic types correctly" do
      assert Type.map_type_to_typespec("string") == "String.t()"
      assert Type.map_type_to_typespec("integer") == "integer()"
      assert Type.map_type_to_typespec("float") == "float()"
      assert Type.map_type_to_typespec("boolean") == "boolean()"
      assert Type.map_type_to_typespec("map") == "map()"
      assert Type.map_type_to_typespec("array") == "list()"
    end

    test "returns term() for unknown types" do
      assert Type.map_type_to_typespec("unknown") == "term()"
    end
  end
end
