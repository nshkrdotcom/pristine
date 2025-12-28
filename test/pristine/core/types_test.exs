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
end
