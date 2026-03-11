defmodule Pristine.OAuth2.Browser do
  @moduledoc """
  Best-effort browser launcher for interactive OAuth flows.
  """

  @type runner :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @spec open(String.t(), keyword()) :: :ok | {:error, term()}
  def open(url, opts \\ []) when is_binary(url) and is_list(opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    os_type = Keyword.get(opts, :os_type, :os.type())

    with {:ok, {command, args}} <- command_for_os(os_type),
         {:ok, output} <- run_command(runner, command, args ++ [url]) do
      case output do
        {_stdout, 0} -> :ok
        {stdout, status} -> {:error, {:command_failed, command, status, stdout}}
      end
    end
  end

  defp command_for_os({:unix, :darwin}), do: {:ok, {"open", []}}
  defp command_for_os({:unix, _flavor}), do: {:ok, {"xdg-open", []}}
  defp command_for_os({:win32, _flavor}), do: {:ok, {"cmd", ["/c", "start", ""]}}
  defp command_for_os(other), do: {:error, {:unsupported_os, other}}

  defp run_command(runner, command, args) when is_function(runner, 3) do
    {:ok, runner.(command, args, stderr_to_stdout: true)}
  rescue
    error in ErlangError ->
      {:error, {:command_unavailable, command, error.original}}

    error in ArgumentError ->
      {:error, {:command_unavailable, command, error.message}}
  end
end
