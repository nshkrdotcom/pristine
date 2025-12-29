defmodule Pristine.Core.UrlTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Url

  test "joins base url and path" do
    assert Url.build("https://example.com", "/v1/echo", %{}, %{}) == "https://example.com/v1/echo"
    assert Url.build("https://example.com/", "v1/echo", %{}, %{}) == "https://example.com/v1/echo"
  end

  test "applies path params" do
    assert Url.build("https://example.com", "/v1/models/{id}", %{"id" => "abc"}, %{}) ==
             "https://example.com/v1/models/abc"

    assert Url.build("https://example.com", "/v1/models/:id", %{id: "abc"}, %{}) ==
             "https://example.com/v1/models/abc"
  end

  test "appends query params" do
    url = Url.build("https://example.com", "/v1/echo", %{}, %{"q" => "hello", limit: 10})
    assert url == "https://example.com/v1/echo?limit=10&q=hello"
  end

  test "applies query format options" do
    query = %{tags: ["a", "b"]}
    expected = URI.encode_query([{"tags[]", "a"}, {"tags[]", "b"}])

    url = Url.build("https://example.com", "/v1/echo", %{}, query, array_format: :brackets)

    assert url == "https://example.com/v1/echo?" <> expected
  end
end
