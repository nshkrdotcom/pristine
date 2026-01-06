defmodule Tinkex.Types.TensorDtypeTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.TensorDtype

  describe "parse/1" do
    test "parses int64 string" do
      assert TensorDtype.parse("int64") == :int64
    end

    test "parses float32 string" do
      assert TensorDtype.parse("float32") == :float32
    end

    test "returns nil for nil input" do
      assert TensorDtype.parse(nil) == nil
    end

    test "returns nil for unknown type" do
      assert TensorDtype.parse("float64") == nil
      assert TensorDtype.parse("int32") == nil
      assert TensorDtype.parse("unknown") == nil
    end
  end

  describe "to_string/1" do
    test "converts int64 atom to string" do
      assert TensorDtype.to_string(:int64) == "int64"
    end

    test "converts float32 atom to string" do
      assert TensorDtype.to_string(:float32) == "float32"
    end
  end

  describe "values/0" do
    test "returns all supported dtypes" do
      values = TensorDtype.values()

      assert :int64 in values
      assert :float32 in values
      assert length(values) == 2
    end
  end

  describe "valid?/1" do
    test "returns true for valid dtypes" do
      assert TensorDtype.valid?(:int64) == true
      assert TensorDtype.valid?(:float32) == true
    end

    test "returns false for invalid dtypes" do
      assert TensorDtype.valid?(:float64) == false
      assert TensorDtype.valid?(:int32) == false
      assert TensorDtype.valid?("int64") == false
    end
  end

  describe "roundtrip" do
    test "parse and to_string are inverse operations" do
      for dtype <- [:int64, :float32] do
        string = TensorDtype.to_string(dtype)
        parsed = TensorDtype.parse(string)
        assert parsed == dtype
      end
    end
  end
end
