defmodule Pristine.OpenAPI.ClientTest do
  use ExUnit.Case, async: true

  alias Pristine.Core.Url
  alias Pristine.OpenAPI.Client

  test "to_request_spec/1 prefers path_template so runtime encoding still happens" do
    spec =
      Client.to_request_spec(%{
        args: %{},
        call: {__MODULE__, :request},
        method: :get,
        path_template: "/v1/widgets/{id}",
        url: "/v1/widgets/a b",
        path_params: %{"id" => "a b"},
        query: %{},
        body: %{},
        form_data: %{}
      })

    assert spec.path == "/v1/widgets/{id}"

    assert Url.build("https://example.com", spec.path, spec.path_params, spec.query) ==
             "https://example.com/v1/widgets/a%20b"
  end

  test "to_request_spec/1 keeps url as a backward-compatible path fallback" do
    spec =
      Client.to_request_spec(%{
        args: %{},
        call: {__MODULE__, :request},
        method: :get,
        url: "/v1/widgets/fallback",
        path_params: %{},
        query: %{},
        body: %{},
        form_data: %{}
      })

    assert spec.path == "/v1/widgets/fallback"
  end
end
