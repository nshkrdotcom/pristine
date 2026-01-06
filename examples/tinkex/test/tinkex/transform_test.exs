defmodule Tinkex.TransformTest do
  use ExUnit.Case, async: true

  alias Tinkex.Transform
  alias Tinkex.NotGiven

  describe "transform/2 with nil" do
    test "returns nil for nil input" do
      assert Transform.transform(nil) == nil
    end
  end

  describe "transform/2 with lists" do
    test "transforms list elements" do
      input = [%{a: 1}, %{b: 2}]
      result = Transform.transform(input)
      assert result == [%{"a" => 1}, %{"b" => 2}]
    end

    test "handles empty list" do
      assert Transform.transform([]) == []
    end

    test "handles nested lists" do
      input = [%{items: [%{x: 1}, %{y: 2}]}]
      result = Transform.transform(input)
      assert result == [%{"items" => [%{"x" => 1}, %{"y" => 2}]}]
    end
  end

  describe "transform/2 with maps" do
    test "stringifies atom keys" do
      result = Transform.transform(%{temperature: 0.7, max_tokens: 100})
      assert result == %{"temperature" => 0.7, "max_tokens" => 100}
    end

    test "preserves string keys" do
      result = Transform.transform(%{"already_string" => "value"})
      assert result == %{"already_string" => "value"}
    end

    test "converts other key types to string" do
      result = Transform.transform(%{123 => "numeric_key"})
      assert result == %{"123" => "numeric_key"}
    end

    test "handles empty map" do
      assert Transform.transform(%{}) == %{}
    end
  end

  describe "transform/2 with structs" do
    defmodule TestStruct do
      defstruct [:name, :value]
    end

    test "converts struct to map" do
      struct = %TestStruct{name: "test", value: 42}
      result = Transform.transform(struct)
      assert result == %{"name" => "test", "value" => 42}
    end

    test "removes __struct__ key" do
      struct = %TestStruct{name: "test", value: 42}
      result = Transform.transform(struct)
      refute Map.has_key?(result, :__struct__)
      refute Map.has_key?(result, "__struct__")
    end
  end

  describe "transform/2 with NotGiven sentinels" do
    test "drops NotGiven values" do
      input = %{
        temperature: 0.7,
        max_tokens: NotGiven.value()
      }

      result = Transform.transform(input)
      assert result == %{"temperature" => 0.7}
    end

    test "drops omit values" do
      input = %{
        temperature: 0.7,
        top_p: NotGiven.omit()
      }

      result = Transform.transform(input)
      assert result == %{"temperature" => 0.7}
    end

    test "preserves nil values by default" do
      input = %{temperature: 0.7, max_tokens: nil}
      result = Transform.transform(input)
      assert result == %{"temperature" => 0.7, "max_tokens" => nil}
    end
  end

  describe "transform/2 with drop_nil? option" do
    test "drops nil values when enabled" do
      input = %{temperature: 0.7, max_tokens: nil}
      result = Transform.transform(input, drop_nil?: true)
      assert result == %{"temperature" => 0.7}
    end

    test "preserves non-nil values" do
      input = %{temperature: 0.7, max_tokens: 0}
      result = Transform.transform(input, drop_nil?: true)
      assert result == %{"temperature" => 0.7, "max_tokens" => 0}
    end

    test "preserves false values" do
      input = %{enabled: false, disabled: nil}
      result = Transform.transform(input, drop_nil?: true)
      assert result == %{"enabled" => false}
    end
  end

  describe "transform/2 with aliases" do
    test "renames keys using aliases" do
      input = %{temp: 0.7, max_tok: 100}
      aliases = %{temp: "temperature", max_tok: "max_tokens"}
      result = Transform.transform(input, aliases: aliases)
      assert result == %{"temperature" => 0.7, "max_tokens" => 100}
    end

    test "handles atom and string alias keys" do
      input = %{temp: 0.7}
      aliases = %{"temp" => "temperature"}
      result = Transform.transform(input, aliases: aliases)
      assert result == %{"temperature" => 0.7}
    end

    test "preserves keys without aliases" do
      input = %{temp: 0.7, unchanged: "value"}
      aliases = %{temp: "temperature"}
      result = Transform.transform(input, aliases: aliases)
      assert result == %{"temperature" => 0.7, "unchanged" => "value"}
    end
  end

  describe "transform/2 with formats" do
    test "formats DateTime to ISO8601" do
      dt = ~U[2024-01-15 12:30:00Z]
      input = %{created_at: dt}
      result = Transform.transform(input, formats: %{created_at: :iso8601})
      assert result == %{"created_at" => "2024-01-15T12:30:00Z"}
    end

    test "formats NaiveDateTime to ISO8601" do
      ndt = ~N[2024-01-15 12:30:00]
      input = %{created_at: ndt}
      result = Transform.transform(input, formats: %{created_at: :iso8601})
      assert result == %{"created_at" => "2024-01-15T12:30:00"}
    end

    test "formats Date to ISO8601" do
      date = ~D[2024-01-15]
      input = %{date: date}
      result = Transform.transform(input, formats: %{date: :iso8601})
      assert result == %{"date" => "2024-01-15"}
    end

    test "applies custom formatter function" do
      input = %{price: 1000}
      formatter = fn cents -> "$#{Float.round(cents / 100, 2)}" end
      result = Transform.transform(input, formats: %{price: formatter})
      assert result == %{"price" => "$10.0"}
    end

    test "handles format lookup by string key" do
      dt = ~U[2024-01-15 12:30:00Z]
      input = %{created_at: dt}
      result = Transform.transform(input, formats: %{"created_at" => :iso8601})
      assert result == %{"created_at" => "2024-01-15T12:30:00Z"}
    end

    test "passes through values without matching format" do
      input = %{name: "test", unformatted: 123}
      result = Transform.transform(input, formats: %{name: fn x -> String.upcase(x) end})
      assert result == %{"name" => "TEST", "unformatted" => 123}
    end
  end

  describe "transform/2 with nested data" do
    test "recursively transforms nested maps" do
      input = %{
        outer: %{
          inner: %{value: 1}
        }
      }

      result = Transform.transform(input)

      assert result == %{
               "outer" => %{
                 "inner" => %{"value" => 1}
               }
             }
    end

    test "drops NotGiven in nested maps" do
      input = %{
        config: %{
          setting: "value",
          omitted: NotGiven.value()
        }
      }

      result = Transform.transform(input)
      assert result == %{"config" => %{"setting" => "value"}}
    end

    test "transforms nested lists of maps" do
      input = %{
        items: [
          %{name: "first", skip: NotGiven.value()},
          %{name: "second"}
        ]
      }

      result = Transform.transform(input)
      assert result == %{"items" => [%{"name" => "first"}, %{"name" => "second"}]}
    end
  end

  describe "transform/2 with primitives" do
    test "returns primitives unchanged" do
      assert Transform.transform("string") == "string"
      assert Transform.transform(123) == 123
      assert Transform.transform(1.5) == 1.5
      assert Transform.transform(true) == true
      assert Transform.transform(:atom) == :atom
    end
  end

  describe "combined options" do
    test "applies aliases, formats, and drop_nil? together" do
      dt = ~U[2024-01-15 12:30:00Z]

      input = %{
        temp: 0.7,
        created: dt,
        optional: nil,
        missing: NotGiven.value()
      }

      result =
        Transform.transform(input,
          aliases: %{temp: "temperature"},
          formats: %{created: :iso8601},
          drop_nil?: true
        )

      assert result == %{
               "temperature" => 0.7,
               "created" => "2024-01-15T12:30:00Z"
             }
    end
  end
end
