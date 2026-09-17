defmodule Pristine.SDK.ProviderProfileTest do
  use ExUnit.Case, async: true

  alias Pristine.SDK.ProviderProfile

  test "status ranges resolve inclusively with exact override precedence" do
    assert ProviderProfile.new!(provider: :demo).status_retry_ranges == []

    profile =
      ProviderProfile.new!(
        provider: :demo,
        status_retry_ranges: [%{"retry?" => true, :range => 500..599}],
        status_retry_overrides: %{503 => %{retry?: false}}
      )

    for status <- [500, 550, 599] do
      assert ProviderProfile.status_retry_override(profile, status) == %{retry?: true}
    end

    for status <- [499, 600] do
      assert ProviderProfile.status_retry_override(profile, status) == nil
    end

    assert ProviderProfile.status_retry_override(profile, 503) == %{retry?: false}
  end

  test "invalid and overlapping ranges are rejected at construction" do
    for entries <- [
          nil,
          %{},
          [nil],
          [%{}],
          [%{range: 599..500//-1}],
          [%{range: 500..599//2}],
          [%{range: 99..200}],
          [%{range: 500..600}],
          [%{range: 500..550}, %{range: 550..599}]
        ] do
      assert {:error, {:invalid_status_retry_ranges, _}} =
               ProviderProfile.new(provider: :demo, status_retry_ranges: entries)

      assert_raise ArgumentError, fn ->
        ProviderProfile.new!(provider: :demo, status_retry_ranges: entries)
      end
    end

    assert {:ok, _} =
             ProviderProfile.new(
               provider: :demo,
               status_retry_ranges: [%{range: 500..550}, %{range: 551..599}]
             )
  end

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
