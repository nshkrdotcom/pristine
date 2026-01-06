defmodule Tinkex.Multipart.FormSerializerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.FormSerializer

  describe "serialize_form_fields/1" do
    test "returns empty map for nil" do
      assert FormSerializer.serialize_form_fields(nil) == %{}
    end

    test "returns empty map for empty map" do
      assert FormSerializer.serialize_form_fields(%{}) == %{}
    end

    test "returns empty map for non-map input" do
      assert FormSerializer.serialize_form_fields("string") == %{}
      assert FormSerializer.serialize_form_fields(123) == %{}
      assert FormSerializer.serialize_form_fields([1, 2, 3]) == %{}
    end

    test "serializes flat map with string keys" do
      result = FormSerializer.serialize_form_fields(%{"name" => "test", "value" => "123"})
      assert result == %{"name" => "test", "value" => "123"}
    end

    test "serializes flat map with atom keys" do
      result = FormSerializer.serialize_form_fields(%{name: "test", value: "123"})
      assert result == %{"name" => "test", "value" => "123"}
    end

    test "serializes nested map using bracket notation" do
      result = FormSerializer.serialize_form_fields(%{user: %{name: "alice", age: 30}})
      assert result == %{"user[name]" => "alice", "user[age]" => "30"}
    end

    test "serializes deeply nested map" do
      result =
        FormSerializer.serialize_form_fields(%{
          user: %{
            profile: %{
              name: "alice"
            }
          }
        })

      assert result == %{"user[profile][name]" => "alice"}
    end

    test "serializes list with bracket notation" do
      result = FormSerializer.serialize_form_fields(%{tags: ["a", "b", "c"]})
      assert result == %{"tags[]" => ["a", "b", "c"]}
    end

    test "serializes nested list items" do
      result = FormSerializer.serialize_form_fields(%{items: [%{name: "a"}, %{name: "b"}]})
      assert result == %{"items[][name]" => ["a", "b"]}
    end

    test "normalizes nil values to empty string" do
      result = FormSerializer.serialize_form_fields(%{empty: nil})
      assert result == %{"empty" => ""}
    end

    test "normalizes integer values to string" do
      result = FormSerializer.serialize_form_fields(%{count: 42})
      assert result == %{"count" => "42"}
    end

    test "normalizes atom values to string" do
      result = FormSerializer.serialize_form_fields(%{status: :active})
      assert result == %{"status" => "active"}
    end

    test "normalizes integer keys to string" do
      result = FormSerializer.serialize_form_fields(%{1 => "one", 2 => "two"})
      assert result == %{"1" => "one", "2" => "two"}
    end

    test "handles mixed key types" do
      result = FormSerializer.serialize_form_fields(%{"string" => "a", :atom => "b", 1 => "c"})
      assert result == %{"string" => "a", "atom" => "b", "1" => "c"}
    end

    test "complex nested structure" do
      input = %{
        model: "gpt-4",
        messages: [
          %{role: "user", content: "hello"},
          %{role: "assistant", content: "hi"}
        ],
        metadata: %{
          source: "api",
          version: 1
        }
      }

      result = FormSerializer.serialize_form_fields(input)

      assert result["model"] == "gpt-4"
      assert result["messages[][role]"] == ["user", "assistant"]
      assert result["messages[][content]"] == ["hello", "hi"]
      assert result["metadata[source]"] == "api"
      assert result["metadata[version]"] == "1"
    end
  end
end
