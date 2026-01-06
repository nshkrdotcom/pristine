defmodule Tinkex.Types.TensorDataTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.TensorData

  describe "struct/0" do
    test "has correct fields" do
      tensor = %TensorData{data: [1, 2, 3], dtype: :int64, shape: [3]}

      assert tensor.data == [1, 2, 3]
      assert tensor.dtype == :int64
      assert tensor.shape == [3]
    end

    test "allows nil shape for scalar/flat data" do
      tensor = %TensorData{data: [42], dtype: :int64, shape: nil}
      assert tensor.shape == nil
    end
  end

  describe "new/3" do
    test "creates TensorData with all fields" do
      tensor = TensorData.new([1.0, 2.0, 3.0], :float32, [3])

      assert tensor.data == [1.0, 2.0, 3.0]
      assert tensor.dtype == :float32
      assert tensor.shape == [3]
    end

    test "creates TensorData without shape" do
      tensor = TensorData.new([1, 2, 3], :int64)

      assert tensor.data == [1, 2, 3]
      assert tensor.dtype == :int64
      assert tensor.shape == nil
    end

    test "creates multi-dimensional tensor data" do
      tensor = TensorData.new([1.0, 2.0, 3.0, 4.0], :float32, [2, 2])

      assert tensor.shape == [2, 2]
    end
  end

  describe "tolist/1" do
    test "returns flat data list" do
      tensor = TensorData.new([1.0, 2.0, 3.0], :float32, [3])

      assert TensorData.tolist(tensor) == [1.0, 2.0, 3.0]
    end

    test "returns data for scalar" do
      tensor = TensorData.new([42], :int64, nil)

      assert TensorData.tolist(tensor) == [42]
    end
  end

  describe "JSON encoding" do
    test "encodes int64 tensor correctly" do
      tensor = TensorData.new([1, 2, 3], :int64, [3])
      json = Jason.encode!(tensor)
      decoded = Jason.decode!(json)

      assert decoded["data"] == [1, 2, 3]
      assert decoded["dtype"] == "int64"
      assert decoded["shape"] == [3]
    end

    test "encodes float32 tensor correctly" do
      tensor = TensorData.new([1.5, 2.5, 3.5], :float32, [3])
      json = Jason.encode!(tensor)
      decoded = Jason.decode!(json)

      assert decoded["data"] == [1.5, 2.5, 3.5]
      assert decoded["dtype"] == "float32"
      assert decoded["shape"] == [3]
    end

    test "encodes multi-dimensional tensor" do
      tensor = TensorData.new([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], :float32, [2, 3])
      json = Jason.encode!(tensor)
      decoded = Jason.decode!(json)

      assert decoded["shape"] == [2, 3]
    end

    test "encodes tensor without shape" do
      tensor = TensorData.new([42], :int64, nil)
      json = Jason.encode!(tensor)
      decoded = Jason.decode!(json)

      assert decoded["data"] == [42]
      assert decoded["dtype"] == "int64"
      # shape should be omitted or null
      assert decoded["shape"] == nil or not Map.has_key?(decoded, "shape")
    end
  end

  describe "from_map/1" do
    test "creates TensorData from decoded JSON map" do
      map = %{
        "data" => [1.0, 2.0, 3.0],
        "dtype" => "float32",
        "shape" => [3]
      }

      tensor = TensorData.from_map(map)

      assert tensor.data == [1.0, 2.0, 3.0]
      assert tensor.dtype == :float32
      assert tensor.shape == [3]
    end

    test "handles nil shape" do
      map = %{
        "data" => [42],
        "dtype" => "int64",
        "shape" => nil
      }

      tensor = TensorData.from_map(map)

      assert tensor.shape == nil
    end

    test "handles missing shape key" do
      map = %{
        "data" => [1, 2],
        "dtype" => "int64"
      }

      tensor = TensorData.from_map(map)

      assert tensor.data == [1, 2]
      assert tensor.shape == nil
    end
  end
end
