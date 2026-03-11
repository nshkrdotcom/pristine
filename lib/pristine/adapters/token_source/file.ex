defmodule Pristine.Adapters.TokenSource.File do
  @moduledoc """
  JSON file-backed token source for reusable OAuth2 token persistence.

  Options:

  - `:path` - required file path
  - `:create_dirs?` - when true, create the parent directory before writes
  """

  @behaviour Pristine.Ports.TokenSource

  alias Pristine.OAuth2.Token

  @file_mode 0o600

  @impl true
  def fetch(opts) do
    with {:ok, path} <- fetch_path(opts),
         {:ok, contents} <- read_file(path),
         {:ok, decoded} <- decode_json(contents),
         {:ok, token_map} <- ensure_map(decoded) do
      {:ok, Token.from_map(token_map)}
    end
  end

  @impl true
  def put(%Token{} = token, opts) do
    with {:ok, path} <- fetch_path(opts),
         :ok <- ensure_parent_directory(path, opts),
         {:ok, payload} <- encode_json(token),
         :ok <- atomic_write(path, payload) do
      :ok
    end
  end

  def put(_token, _opts), do: {:error, :invalid_token}

  defp fetch_path(opts) do
    case Keyword.get(opts, :path) do
      path when is_binary(path) and path != "" -> {:ok, path}
      _other -> {:error, :missing_path}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> :error
      {:error, reason} -> {:error, {:token_file_read_failed, reason}}
    end
  end

  defp decode_json(contents) do
    case Jason.decode(contents) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:invalid_token_json, reason}}
    end
  end

  defp ensure_map(%{} = map), do: {:ok, map}
  defp ensure_map(_other), do: {:error, :invalid_token_data}

  defp ensure_parent_directory(path, opts) do
    directory = Path.dirname(path)

    cond do
      File.dir?(directory) ->
        :ok

      Keyword.get(opts, :create_dirs?, false) ->
        case File.mkdir_p(directory) do
          :ok -> :ok
          {:error, reason} -> {:error, {:token_directory_create_failed, reason}}
        end

      true ->
        {:error, :missing_token_directory}
    end
  end

  defp encode_json(%Token{} = token) do
    payload =
      token
      |> Token.to_map()
      |> Jason.encode_to_iodata!(pretty: true)

    {:ok, [payload, ?\n]}
  rescue
    error in Jason.EncodeError -> {:error, {:token_file_encode_failed, error}}
  end

  defp atomic_write(path, payload) do
    temp_path = temporary_path(path)

    with :ok <- write_temp_file(temp_path, payload),
         :ok <- chmod(temp_path),
         :ok <- rename(temp_path, path),
         :ok <- chmod(path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temp_path)
        {:error, reason}
    end
  end

  defp write_temp_file(path, payload) do
    case File.write(path, payload, [:binary]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_file_write_failed, reason}}
    end
  end

  defp rename(source, destination) do
    case File.rename(source, destination) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_file_rename_failed, reason}}
    end
  end

  defp chmod(path) do
    case File.chmod(path, @file_mode) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_file_chmod_failed, reason}}
    end
  end

  defp temporary_path(path) do
    directory = Path.dirname(path)
    basename = Path.basename(path)
    suffix = System.unique_integer([:positive, :monotonic])

    Path.join(directory, ".#{basename}.#{suffix}.tmp")
  end
end
