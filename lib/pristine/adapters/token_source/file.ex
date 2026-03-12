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
         {:ok, token_map} <- ensure_map(decoded),
         :ok <- validate_token_map(token_map) do
      {:ok, Token.from_map(token_map)}
    end
  end

  @impl true
  def put(%Token{} = token, opts) do
    with :ok <- validate_token(token),
         {:ok, path} <- fetch_path(opts),
         :ok <- ensure_parent_directory(path, opts),
         {:ok, payload} <- encode_json(token) do
      atomic_write(path, payload)
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

  defp validate_token(%Token{} = token) do
    token
    |> Token.to_map()
    |> validate_token_map()
  end

  defp validate_token_map(map) when is_map(map) do
    with :ok <- validate_optional_string_field(map, :access_token),
         :ok <- validate_optional_string_field(map, :refresh_token),
         :ok <- validate_optional_integer_field(map, :expires_at),
         :ok <- validate_optional_non_empty_string_field(map, :token_type) do
      validate_optional_map_field(map, :other_params)
    end
  end

  defp validate_optional_string_field(map, key) do
    case fetch_field(map, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _other -> {:error, {:invalid_token_data, {key, :expected_string_or_nil}}}
    end
  end

  defp validate_optional_integer_field(map, key) do
    case fetch_field(map, key) do
      nil -> :ok
      value when is_integer(value) -> :ok
      _other -> {:error, {:invalid_token_data, {key, :expected_integer_or_nil}}}
    end
  end

  defp validate_optional_non_empty_string_field(map, key) do
    case fetch_field(map, key) do
      nil -> :ok
      value when is_binary(value) and value != "" -> :ok
      _other -> {:error, {:invalid_token_data, {key, :expected_non_empty_string_or_nil}}}
    end
  end

  defp validate_optional_map_field(map, key) do
    case fetch_field(map, key) do
      nil -> :ok
      value when is_map(value) -> :ok
      _other -> {:error, {:invalid_token_data, {key, :expected_map_or_nil}}}
    end
  end

  defp fetch_field(map, key) when is_map(map) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

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
    case File.open(path, [:binary, :exclusive, :write]) do
      {:ok, device} ->
        try do
          with :ok <- chmod(path),
               :ok <- write_device(device, payload) do
            sync_device(device)
          end
        after
          File.close(device)
        end

      {:error, reason} ->
        {:error, {:token_file_open_failed, reason}}
    end
  end

  defp write_device(device, payload) do
    case :file.write(device, payload) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_file_write_failed, reason}}
    end
  end

  defp sync_device(device) do
    case :file.sync(device) do
      :ok -> :ok
      {:error, reason} -> {:error, {:token_file_sync_failed, reason}}
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
