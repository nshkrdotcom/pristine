defmodule Pristine.Core.HeadersTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Headers

  test "merges headers and applies content type" do
    {:ok, headers} =
      Headers.build(
        %{"X-Base" => "1"},
        %{"X-Endpoint" => "2"},
        [],
        %{"X-Extra" => "3"},
        "application/json"
      )

    assert headers["X-Base"] == "1"
    assert headers["X-Endpoint"] == "2"
    assert headers["X-Extra"] == "3"
    assert headers["content-type"] == "application/json"
  end
end
