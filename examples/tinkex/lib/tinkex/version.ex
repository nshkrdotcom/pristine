defmodule Tinkex.Version do
  @moduledoc false

  @version "0.1.0"
  @tinker_sdk_version "tinkex-elixir-0.1.0"

  @spec current() :: String.t()
  def current, do: @version

  @spec tinker_sdk() :: String.t()
  def tinker_sdk, do: @tinker_sdk_version
end
