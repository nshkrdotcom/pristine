defmodule Pristine.Core.TypesTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Types

  test "compiles manifest types into sinter schemas" do
    types = %{
      "SampleRequest" => %{
        fields: %{
          prompt: %{type: "string", required: true, min_length: 1},
          count: %{type: "integer", optional: true, default: 1}
        }
      }
    }

    compiled = Types.compile(types)
    assert Map.has_key?(compiled, "SampleRequest")

    schema = compiled["SampleRequest"]
    assert schema.fields["prompt"].constraints[:min_length] == 1
    assert schema.fields["count"].default == 1
  end

  test "compiles unions, literals, and type references" do
    types = %{
      "TextChunk" => %{
        fields: %{
          type: %{type: "literal", value: "text"},
          content: %{type: "string", required: true}
        }
      },
      "ImageChunk" => %{
        fields: %{
          type: %{type: "literal", value: "image"},
          url: %{type: "string", required: true}
        }
      },
      "ModelInputChunk" => %{
        kind: :union,
        discriminator: %{
          field: "type",
          mapping: %{"text" => "TextChunk", "image" => "ImageChunk"}
        }
      },
      "ModelInput" => %{
        fields: %{
          chunks: %{type: "array", items: %{type_ref: "ModelInputChunk"}}
        }
      }
    }

    compiled = Types.compile(types)

    assert match?({:discriminated_union, _}, compiled["ModelInputChunk"])

    text_schema = compiled["TextChunk"]
    assert text_schema.fields["type"].type == {:literal, "text"}

    model_input_schema = compiled["ModelInput"]
    assert {:array, {:discriminated_union, _}} = model_input_schema.fields["chunks"].type
  end
end
