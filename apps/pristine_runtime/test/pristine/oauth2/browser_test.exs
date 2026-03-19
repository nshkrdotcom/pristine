defmodule Pristine.OAuth2.BrowserTest do
  use ExUnit.Case, async: true

  alias Pristine.OAuth2.Browser

  test "opens a browser with the platform command" do
    test_pid = self()

    runner = fn command, args, _opts ->
      send(test_pid, {:browser_command, command, args})
      {"", 0}
    end

    assert :ok =
             Browser.open("https://example.com/oauth",
               os_type: {:unix, :linux},
               runner: runner
             )

    assert_receive {:browser_command, "xdg-open", ["https://example.com/oauth"]}
  end

  test "returns command failures without raising" do
    runner = fn _command, _args, _opts -> {"failed to open", 1} end

    assert {:error, {:command_failed, "open", 1, "failed to open"}} =
             Browser.open("https://example.com/oauth",
               os_type: {:unix, :darwin},
               runner: runner
             )
  end

  test "returns an unsupported-os error" do
    assert {:error, {:unsupported_os, {:plan9, :none}}} =
             Browser.open("https://example.com/oauth", os_type: {:plan9, :none})
  end
end
