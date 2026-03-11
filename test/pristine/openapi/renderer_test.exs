defmodule Pristine.OpenAPI.RendererTest do
  use ExUnit.Case, async: true

  alias Pristine.OpenAPI.Renderer, as: OpenAPIRenderer

  test "rewrites nested pristine module references to local aliases in rendered source" do
    source = """
    defmodule Example do
      @moduledoc false
      use Pristine.OpenAPI.Operation

      @spec provider() :: Pristine.OAuth2.Provider.t()
      def provider do
        Pristine.OAuth2.Provider.new(name: "example")
      end

      def decode(data) do
        Pristine.OpenAPI.Runtime.decode_module_type(__MODULE__, :t, data)
      end
    end
    """

    source = OpenAPIRenderer.rewrite_nested_module_aliases_in_source(source)

    assert source =~ "alias Pristine.OAuth2, as: OAuth2"
    assert source =~ "alias Pristine.OpenAPI.Runtime, as: OpenAPIRuntime"
    assert source =~ "@spec provider() :: OAuth2.Provider.t()"
    assert source =~ "OAuth2.Provider.new(name: \"example\")"
    assert source =~ "OpenAPIRuntime.decode_module_type(__MODULE__, :t, data)"
    refute source =~ "Pristine.OAuth2.Provider.new"
    refute source =~ "Pristine.OpenAPI.Runtime.decode_module_type"
  end
end
