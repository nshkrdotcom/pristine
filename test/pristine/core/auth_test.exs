defmodule Pristine.Core.AuthTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Auth

  test "applies multiple auth modules" do
    auths = [
      {Pristine.Adapters.Auth.ApiKey, [value: "secret", header: "X-API-Key"]},
      {Pristine.Adapters.Auth.Bearer, [token: "token"]}
    ]

    assert {:ok, headers} = Auth.apply(auths, %{"X-Base" => "1"})
    assert headers["X-Base"] == "1"
    assert headers["X-API-Key"] == "secret"
    assert headers["Authorization"] == "Bearer token"
  end
end
