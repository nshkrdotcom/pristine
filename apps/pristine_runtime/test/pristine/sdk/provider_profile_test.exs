defmodule Pristine.SDK.ProviderProfileTest do
  use ExUnit.Case, async: true

  alias Pristine.SDK.ProviderProfile

  test "status retry overrides keep only bounded keys" do
    profile =
      ProviderProfile.new!(%{
        provider: :demo,
        status_retry_overrides: %{
          "429" => %{
            "retry?" => true,
            "retry_groups" => ["core"],
            "unknown_status_flag" => "provider-authored"
          }
        }
      })

    assert ProviderProfile.status_retry_override(profile, 429) == %{
             retry?: true,
             retry_groups: ["core"]
           }
  end

  test "safe string methods stay bounded for default retry decisions" do
    assert ProviderProfile.retryable_group?(nil, %{"method" => "TRACE"})
    refute ProviderProfile.retryable_group?(nil, %{"method" => "CUSTOM_PROVIDER_METHOD"})
  end
end
