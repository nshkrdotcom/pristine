defmodule Pristine.OAuth2.TokenTest do
  use ExUnit.Case, async: true

  alias Pristine.OAuth2.Token

  test "preserves provider metadata from raw backend token maps" do
    token =
      Token.from_backend_token(%{
        "access_token" => "secret_access",
        "refresh_token" => "secret_refresh",
        "token_type" => "bearer",
        "bot_id" => "bot-123",
        "workspace_id" => "workspace-123",
        "owner" => %{"type" => "workspace", "workspace" => true}
      })

    assert token.access_token == "secret_access"
    assert token.refresh_token == "secret_refresh"
    assert token.token_type == "Bearer"

    assert token.other_params == %{
             "bot_id" => "bot-123",
             "owner" => %{"type" => "workspace", "workspace" => true},
             "workspace_id" => "workspace-123"
           }
  end

  test "keeps explicit other_params when the backend already split them out" do
    token =
      Token.from_backend_token(%{
        access_token: "secret_access",
        other_params: %{"bot_id" => "bot-123"}
      })

    assert token.other_params == %{"bot_id" => "bot-123"}
  end
end
