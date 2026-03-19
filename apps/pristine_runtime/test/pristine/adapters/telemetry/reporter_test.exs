defmodule Pristine.Adapters.Telemetry.ReporterTest do
  use ExUnit.Case, async: true

  test "does not ship the compatibility telemetry reporter adapter" do
    refute Code.ensure_compiled?(Pristine.Adapters.Telemetry.Reporter)
  end
end
