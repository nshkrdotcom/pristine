defmodule Pristine.Adapters.AuthTest do
  use ExUnit.Case, async: true

  alias Pristine.Adapters.Auth

  test "api key adapter returns header" do
    assert {:ok, headers} = Auth.ApiKey.headers(value: "secret", header: "X-API-Key")
    assert headers == %{"X-API-Key" => "secret"}
  end

  test "bearer adapter returns authorization header" do
    assert {:ok, headers} = Auth.Bearer.headers(token: "token123")
    assert headers == %{"Authorization" => "Bearer token123"}
  end

  test "basic adapter returns authorization header" do
    assert {:ok, headers} = Auth.Basic.headers(username: "client-id", password: "client-secret")

    assert headers == %{
             "Authorization" => "Basic " <> Base.encode64("client-id:client-secret")
           }
  end
end
