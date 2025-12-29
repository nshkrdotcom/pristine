defmodule Pristine.Adapters.Serializer.JSONTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Serializer.JSON

  test "decodes with sinter schema" do
    schema =
      Sinter.Schema.define([
        {:name, :string, [required: true]}
      ])

    assert {:ok, %{"name" => "Ada"}} = JSON.decode(~s({"name":"Ada"}), schema, [])
  end

  test "decodes with discriminated union type spec" do
    text_schema =
      Sinter.Schema.define([
        {:type, {:literal, "text"}, [required: true]},
        {:content, :string, [required: true]}
      ])

    union_type =
      {:discriminated_union, discriminator: "type", variants: %{"text" => text_schema}}

    assert {:ok, %{"type" => "text", "content" => "hello"}} =
             JSON.decode(~s({"type":"text","content":"hello"}), union_type, [])
  end
end
