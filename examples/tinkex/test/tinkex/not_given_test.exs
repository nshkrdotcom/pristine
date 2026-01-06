defmodule Tinkex.NotGivenTest do
  use ExUnit.Case, async: true

  alias Tinkex.NotGiven
  import Tinkex.NotGiven, only: [is_not_given: 1, is_omit: 1]

  describe "value/0" do
    test "returns the not_given sentinel" do
      assert NotGiven.value() == :__tinkex_not_given__
    end

    test "sentinel is consistent across calls" do
      assert NotGiven.value() == NotGiven.value()
    end
  end

  describe "omit/0" do
    test "returns the omit sentinel" do
      assert NotGiven.omit() == :__tinkex_omit__
    end

    test "omit is different from not_given" do
      refute NotGiven.value() == NotGiven.omit()
    end
  end

  describe "not_given?/1" do
    test "returns true for not_given sentinel" do
      assert NotGiven.not_given?(NotGiven.value())
    end

    test "returns false for other atoms" do
      refute NotGiven.not_given?(:some_atom)
      refute NotGiven.not_given?(:not_given)
    end

    test "returns false for nil" do
      refute NotGiven.not_given?(nil)
    end

    test "returns false for omit sentinel" do
      refute NotGiven.not_given?(NotGiven.omit())
    end

    test "returns false for other values" do
      refute NotGiven.not_given?("string")
      refute NotGiven.not_given?(123)
      refute NotGiven.not_given?(%{})
      refute NotGiven.not_given?([])
    end
  end

  describe "is_not_given/1 guard" do
    test "works in function heads" do
      result = check_not_given(NotGiven.value())
      assert result == :not_given

      result2 = check_not_given("other")
      assert result2 == :given
    end

    defp check_not_given(value) when is_not_given(value), do: :not_given
    defp check_not_given(_value), do: :given
  end

  describe "omit?/1" do
    test "returns true for omit sentinel" do
      assert NotGiven.omit?(NotGiven.omit())
    end

    test "returns false for other atoms" do
      refute NotGiven.omit?(:some_atom)
      refute NotGiven.omit?(:omit)
    end

    test "returns false for nil" do
      refute NotGiven.omit?(nil)
    end

    test "returns false for not_given sentinel" do
      refute NotGiven.omit?(NotGiven.value())
    end

    test "returns false for other values" do
      refute NotGiven.omit?("string")
      refute NotGiven.omit?(123)
    end
  end

  describe "is_omit/1 guard" do
    test "works in function heads" do
      result = check_omit(NotGiven.omit())
      assert result == :omit

      result2 = check_omit("other")
      assert result2 == :not_omit
    end

    defp check_omit(value) when is_omit(value), do: :omit
    defp check_omit(_value), do: :not_omit
  end

  describe "coalesce/2" do
    test "returns default for not_given sentinel" do
      assert NotGiven.coalesce(NotGiven.value(), "default") == "default"
    end

    test "returns default for omit sentinel" do
      assert NotGiven.coalesce(NotGiven.omit(), "default") == "default"
    end

    test "returns nil as default when not specified" do
      assert NotGiven.coalesce(NotGiven.value()) == nil
    end

    test "returns original value for non-sentinels" do
      assert NotGiven.coalesce("actual", "default") == "actual"
      assert NotGiven.coalesce(123, 0) == 123
      assert NotGiven.coalesce(%{key: "value"}, %{}) == %{key: "value"}
    end

    test "preserves nil values" do
      assert NotGiven.coalesce(nil, "default") == nil
    end

    test "preserves false values" do
      assert NotGiven.coalesce(false, true) == false
    end

    test "preserves empty collections" do
      assert NotGiven.coalesce([], [1, 2, 3]) == []
      assert NotGiven.coalesce(%{}, %{a: 1}) == %{}
    end
  end

  describe "practical usage" do
    test "building request payloads" do
      opts = [temperature: 0.7, max_tokens: NotGiven.value()]

      payload =
        opts
        |> Enum.reject(fn {_k, v} -> NotGiven.not_given?(v) end)
        |> Map.new()

      assert payload == %{temperature: 0.7}
    end

    test "defaulting omitted values" do
      opts = [
        temperature: NotGiven.value(),
        max_tokens: 100
      ]

      config = %{
        temperature: NotGiven.coalesce(opts[:temperature], 1.0),
        max_tokens: NotGiven.coalesce(opts[:max_tokens], 50)
      }

      assert config.temperature == 1.0
      assert config.max_tokens == 100
    end
  end
end
