defmodule Tinkex.Types.DatumTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{Datum, ModelInput, TensorData}

  describe "struct/0" do
    test "requires model_input field" do
      assert_raise ArgumentError, fn ->
        struct!(Datum, [])
      end
    end

    test "has default empty loss_fn_inputs" do
      model_input = ModelInput.from_ints([1, 2, 3])
      datum = %Datum{model_input: model_input}

      assert datum.loss_fn_inputs == %{}
    end
  end

  describe "new/1" do
    test "creates Datum with ModelInput" do
      model_input = ModelInput.from_ints([1, 2, 3])

      datum = Datum.new(%{model_input: model_input})

      assert datum.model_input == model_input
      assert datum.loss_fn_inputs == %{}
    end

    test "creates Datum with loss_fn_inputs as TensorData" do
      model_input = ModelInput.from_ints([1, 2, 3])
      target_tokens = TensorData.new([4, 5, 6], :int64, [3])

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{"target_tokens" => target_tokens}
        })

      assert datum.model_input == model_input
      assert Map.get(datum.loss_fn_inputs, "target_tokens") == target_tokens
    end

    test "accepts atom keys" do
      model_input = ModelInput.from_ints([1, 2, 3])

      datum = Datum.new(%{model_input: model_input})

      assert datum.model_input == model_input
    end

    test "creates Datum with multiple loss_fn_inputs" do
      model_input = ModelInput.from_ints([1, 2, 3])
      target_tokens = TensorData.new([4, 5, 6], :int64, [3])
      weights = TensorData.new([1.0, 1.0, 1.0], :float32, [3])

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{
            "target_tokens" => target_tokens,
            "weights" => weights
          }
        })

      assert Map.get(datum.loss_fn_inputs, "target_tokens") == target_tokens
      assert Map.get(datum.loss_fn_inputs, "weights") == weights
    end
  end

  describe "JSON encoding" do
    test "encodes basic Datum correctly" do
      model_input = ModelInput.from_ints([1, 2, 3])
      datum = Datum.new(%{model_input: model_input})

      json = Jason.encode!(datum)
      decoded = Jason.decode!(json)

      assert is_map(decoded["model_input"])
      assert decoded["model_input"]["chunks"] |> length() == 1
      assert decoded["loss_fn_inputs"] == %{}
    end

    test "encodes Datum with loss_fn_inputs correctly" do
      model_input = ModelInput.from_ints([1, 2, 3])
      target_tokens = TensorData.new([4, 5, 6], :int64, [3])

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{"target_tokens" => target_tokens}
        })

      json = Jason.encode!(datum)
      decoded = Jason.decode!(json)

      assert decoded["loss_fn_inputs"]["target_tokens"]["data"] == [4, 5, 6]
      assert decoded["loss_fn_inputs"]["target_tokens"]["dtype"] == "int64"
    end

    test "encodes mixed dtype loss_fn_inputs" do
      model_input = ModelInput.from_ints([1])
      target = TensorData.new([2], :int64, [1])
      weight = TensorData.new([0.5], :float32, [1])

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{
            "target_tokens" => target,
            "weights" => weight
          }
        })

      json = Jason.encode!(datum)
      decoded = Jason.decode!(json)

      assert decoded["loss_fn_inputs"]["target_tokens"]["dtype"] == "int64"
      assert decoded["loss_fn_inputs"]["weights"]["dtype"] == "float32"
    end
  end
end
