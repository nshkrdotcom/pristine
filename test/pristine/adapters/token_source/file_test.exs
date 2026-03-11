defmodule Pristine.Adapters.TokenSource.FileTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Pristine.Adapters.TokenSource.File, as: TokenFile
  alias Pristine.OAuth2.Token

  @moduletag :tmp_dir

  test "round-trips tokens through JSON storage", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "oauth.json")

    token = %Token{
      access_token: "secret_access",
      refresh_token: "secret_refresh",
      expires_at: 1_762_345_678,
      token_type: "Bearer",
      other_params: %{
        "bot_id" => "bot-123",
        "owner" => %{"type" => "workspace", "workspace" => true}
      }
    }

    assert :ok = TokenFile.put(token, path: path)
    assert {:ok, loaded} = TokenFile.fetch(path: path)
    assert loaded == token
  end

  test "returns :error for missing files", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing.json")

    assert :error = TokenFile.fetch(path: path)
  end

  test "returns a structured error for malformed JSON", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "broken.json")
    File.write!(path, "{not-json")

    assert {:error, {:invalid_token_json, %Jason.DecodeError{}}} = TokenFile.fetch(path: path)
  end

  test "returns a structured error for malformed token data", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "invalid-structure.json")

    File.write!(
      path,
      Jason.encode!(%{
        "access_token" => 123,
        "other_params" => %{}
      })
    )

    assert {:error, {:invalid_token_data, {:access_token, :expected_string_or_nil}}} =
             TokenFile.fetch(path: path)
  end

  test "forces 0600 permissions on persisted files", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "secure.json")

    assert :ok =
             TokenFile.put(%Token{access_token: "secret_access"}, path: path)

    assert {:ok, stat} = File.stat(path)
    assert band(stat.mode, 0o777) == 0o600
  end

  test "preserves provider metadata in other_params", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "metadata.json")

    token = %Token{
      access_token: "secret_access",
      other_params: %{
        "bot_id" => "bot-123",
        "owner" => %{
          "type" => "user",
          "user" => %{
            "object" => "user",
            "id" => "user-123"
          }
        },
        "workspace_id" => "workspace-123",
        "workspace_name" => "Example Workspace"
      }
    }

    assert :ok = TokenFile.put(token, path: path)

    assert {:ok, %Token{other_params: other_params}} = TokenFile.fetch(path: path)

    assert other_params == token.other_params
  end

  test "creates parent directories when requested", %{tmp_dir: tmp_dir} do
    path = Path.join([tmp_dir, "oauth", "tokens", "saved.json"])

    assert :ok =
             TokenFile.put(%Token{access_token: "secret_access"},
               path: path,
               create_dirs?: true
             )

    assert File.exists?(path)
  end

  test "rejects invalid token structs on write", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "invalid-token.json")

    assert {:error, {:invalid_token_data, {:access_token, :expected_string_or_nil}}} =
             TokenFile.put(%Token{access_token: 123}, path: path)
  end
end
