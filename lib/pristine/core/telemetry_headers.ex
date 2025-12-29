defmodule Pristine.Core.TelemetryHeaders do
  @moduledoc """
  Build platform and retry telemetry headers.
  """

  @spec platform_headers(keyword()) :: map()
  def platform_headers(opts \\ []) do
    package_version = Keyword.get(opts, :package_version)

    headers = %{
      "X-Stainless-OS" => detect_os(),
      "X-Stainless-Arch" => detect_arch(),
      "X-Stainless-Runtime" => "Elixir",
      "X-Stainless-Runtime-Version" => System.version()
    }

    if package_version do
      Map.put(headers, "X-Stainless-Package-Version", to_string(package_version))
    else
      headers
    end
  end

  @spec retry_headers(non_neg_integer() | nil, non_neg_integer() | nil) :: map()
  def retry_headers(retry_count, timeout_ms) do
    %{}
    |> maybe_put("x-stainless-retry-count", retry_count)
    |> maybe_put("x-stainless-read-timeout", timeout_ms)
  end

  defp maybe_put(headers, _key, nil), do: headers
  defp maybe_put(headers, key, value), do: Map.put(headers, key, to_string(value))

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> "MacOS"
      {:unix, :linux} -> "Linux"
      {:unix, other} -> other |> to_string() |> String.capitalize()
      {:win32, _} -> "Windows"
    end
  end

  defp detect_arch do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.downcase()

    cond do
      String.contains?(arch, "aarch64") -> "arm64"
      String.contains?(arch, "arm64") -> "arm64"
      String.contains?(arch, "x86_64") -> "x64"
      String.contains?(arch, "amd64") -> "x64"
      true -> arch
    end
  end
end
