defmodule Pristine.OpenAPI.SecurityTest do
  use ExUnit.Case, async: true

  test "does not ship a fallback-only openapi security reader" do
    refute Code.ensure_compiled?(Pristine.OpenAPI.Security)
  end
end
