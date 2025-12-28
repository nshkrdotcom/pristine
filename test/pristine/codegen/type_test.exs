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
