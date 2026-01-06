defmodule Tinkex.Types.RegularizerTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{RegularizerOutput, RegularizerSpec, TelemetryResponse, TypeAliases}

  describe "RegularizerOutput" do
    test "from_computation/5 creates output with all fields" do
      output = RegularizerOutput.from_computation("l1", 22.4, 0.01, %{"l1_mean" => 22.4}, 7.48)

      assert output.name == "l1"
      assert output.value == 22.4
      assert output.weight == 0.01
      assert_in_delta output.contribution, 0.224, 0.0001
      assert output.grad_norm == 7.48
      assert_in_delta output.grad_norm_weighted, 0.0748, 0.0001
      assert output.custom == %{"l1_mean" => 22.4}
    end

    test "from_computation/4 creates output without grad_norm" do
      output = RegularizerOutput.from_computation("entropy", 1.5, 0.1, %{})

      assert output.name == "entropy"
      assert output.value == 1.5
      assert output.weight == 0.1
      assert_in_delta output.contribution, 0.15, 0.0001
      assert output.grad_norm == nil
      assert output.grad_norm_weighted == nil
      assert output.custom == %{}
    end

    test "from_computation/4 handles nil custom_metrics" do
      output = RegularizerOutput.from_computation("kl", 0.5, 0.05, nil)

      assert output.custom == %{}
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(RegularizerOutput, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(RegularizerOutput, name: "test", value: 1.0, weight: 0.1)
      end
    end

    test "encodes to JSON with gradient fields" do
      output = RegularizerOutput.from_computation("l1", 22.4, 0.01, %{"extra" => 5}, 7.48)

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "l1"
      assert decoded["value"] == 22.4
      assert decoded["weight"] == 0.01
      assert_in_delta decoded["contribution"], 0.224, 0.0001
      assert decoded["grad_norm"] == 7.48
      assert_in_delta decoded["grad_norm_weighted"], 0.0748, 0.0001
      assert decoded["custom"]["extra"] == 5
    end

    test "encodes to JSON without gradient fields when nil" do
      output = RegularizerOutput.from_computation("l2", 10.0, 0.1, %{})

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "l2"
      refute Map.has_key?(decoded, "grad_norm")
      refute Map.has_key?(decoded, "grad_norm_weighted")
    end
  end

  describe "RegularizerSpec" do
    test "new/1 creates spec from map" do
      fun = fn _data, _logprobs -> {0.5, %{}} end

      spec =
        RegularizerSpec.new(%{
          fn: fun,
          weight: 0.01,
          name: "l1"
        })

      assert spec.fn == fun
      assert spec.weight == 0.01
      assert spec.name == "l1"
      assert spec.async == false
    end

    test "new/1 creates spec from keyword list" do
      fun = fn _data, _logprobs -> {0.5, %{}} end

      spec = RegularizerSpec.new(fn: fun, weight: 0.5, name: "entropy", async: true)

      assert spec.fn == fun
      assert spec.weight == 0.5
      assert spec.name == "entropy"
      assert spec.async == true
    end

    test "new/1 defaults async to false" do
      fun = fn _data, _logprobs -> {0.0, %{}} end

      spec = RegularizerSpec.new(fn: fun, weight: 0.1, name: "test")

      assert spec.async == false
    end

    test "validate!/1 raises for non-function fn" do
      assert_raise ArgumentError, ~r/must be a function of arity 2/, fn ->
        RegularizerSpec.new(%{fn: "not a function", weight: 0.1, name: "test"})
      end

      assert_raise ArgumentError, ~r/must be a function of arity 2/, fn ->
        RegularizerSpec.new(%{fn: fn _x -> :ok end, weight: 0.1, name: "test"})
      end
    end

    test "validate!/1 raises for negative weight" do
      fun = fn _d, _l -> {0, %{}} end

      assert_raise ArgumentError, ~r/must be a non-negative number/, fn ->
        RegularizerSpec.new(%{fn: fun, weight: -0.5, name: "test"})
      end
    end

    test "validate!/1 raises for empty name" do
      fun = fn _d, _l -> {0, %{}} end

      assert_raise ArgumentError, ~r/must be a non-empty string/, fn ->
        RegularizerSpec.new(%{fn: fun, weight: 0.1, name: ""})
      end

      assert_raise ArgumentError, ~r/must be a non-empty string/, fn ->
        RegularizerSpec.new(%{fn: fun, weight: 0.1, name: 123})
      end
    end

    test "validate!/1 raises for non-boolean async" do
      fun = fn _d, _l -> {0, %{}} end

      assert_raise ArgumentError, ~r/must be a boolean/, fn ->
        RegularizerSpec.new(%{fn: fun, weight: 0.1, name: "test", async: "yes"})
      end
    end

    test "allows zero weight" do
      fun = fn _d, _l -> {0, %{}} end

      spec = RegularizerSpec.new(fn: fun, weight: 0, name: "disabled")

      assert spec.weight == 0
    end
  end

  describe "TelemetryResponse" do
    test "new/0 creates accepted response" do
      response = TelemetryResponse.new()

      assert response.status == "accepted"
    end

    test "from_json/1 parses string key" do
      response = TelemetryResponse.from_json(%{"status" => "accepted"})

      assert response.status == "accepted"
    end

    test "from_json/1 parses atom key" do
      response = TelemetryResponse.from_json(%{status: "accepted"})

      assert response.status == "accepted"
    end

    test "from_json/1 handles unknown input" do
      response = TelemetryResponse.from_json(%{"other" => "value"})

      assert response.status == "accepted"
    end

    test "default struct has accepted status" do
      response = %TelemetryResponse{}

      assert response.status == "accepted"
    end
  end

  describe "TypeAliases" do
    test "module compiles and is available" do
      assert Code.ensure_loaded?(TypeAliases)
    end

    # TypeAliases only provides @type definitions, no runtime functions
    # The types are used at compile time for dialyzer
  end
end
