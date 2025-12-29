defmodule Pristine.Core.QuerystringTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Querystring

  test "encodes primitives and omits nils" do
    assert Querystring.encode(%{a: nil, b: true, c: false}) == [
             {"b", "true"},
             {"c", "false"}
           ]
  end

  test "encodes nested maps with brackets by default" do
    assert Querystring.encode(%{filter: %{status: "ok"}}) == [
             {"filter[status]", "ok"}
           ]
  end

  test "encodes nested maps with dot notation" do
    assert Querystring.encode(%{filter: %{status: "ok"}}, nested_format: :dots) == [
             {"filter.status", "ok"}
           ]
  end

  test "encodes arrays with repeat format by default" do
    assert Querystring.encode(%{tags: ["a", "b"]}) == [
             {"tags", "a"},
             {"tags", "b"}
           ]
  end

  test "encodes arrays with comma format" do
    assert Querystring.encode(%{tags: ["a", "b"]}, array_format: :comma) == [
             {"tags", "a,b"}
           ]
  end

  test "encodes arrays with brackets format" do
    assert Querystring.encode(%{tags: ["a", "b"]}, array_format: :brackets) == [
             {"tags[]", "a"},
             {"tags[]", "b"}
           ]
  end

  test "encodes arrays with indices format" do
    assert Querystring.encode(%{tags: ["a", "b"]}, array_format: :indices) == [
             {"tags[0]", "a"},
             {"tags[1]", "b"}
           ]
  end
end
