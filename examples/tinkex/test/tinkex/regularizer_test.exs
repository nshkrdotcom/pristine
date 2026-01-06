defmodule Tinkex.RegularizerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer

  # Test module implementing the behaviour
  defmodule TestL1Regularizer do
    @behaviour Tinkex.Regularizer

    @impl true
    def compute(_data, logprobs, _opts) do
      # Sum absolute values (mocked without Nx)
      l1 = Enum.reduce(logprobs, 0, fn x, acc -> acc + abs(x) end)
      {l1, %{"l1_value" => l1}}
    end

    @impl true
    def name, do: "test_l1"
  end

  defmodule TestRegWithoutName do
    @behaviour Tinkex.Regularizer

    @impl true
    def compute(_data, logprobs, _opts) do
      # Mean (mocked without Nx)
      mean = Enum.sum(logprobs) / length(logprobs)
      {mean, %{}}
    end
  end

  describe "execute/4 with anonymous functions" do
    test "executes arity-2 function" do
      fun = fn _data, logprobs -> {Enum.sum(logprobs), %{"sum" => true}} end
      data = []
      logprobs = [1.0, 2.0, 3.0]

      {loss, metrics} = Regularizer.execute(fun, data, logprobs)

      assert loss == 6.0
      assert metrics == %{"sum" => true}
    end

    test "executes arity-3 function with opts" do
      fun = fn _data, logprobs, opts ->
        multiplier = Keyword.get(opts, :multiplier, 1.0)
        {Enum.sum(logprobs) * multiplier, %{}}
      end

      data = []
      logprobs = [1.0, 2.0, 3.0]

      {loss, _} = Regularizer.execute(fun, data, logprobs, multiplier: 2.0)

      assert loss == 12.0
    end

    test "passes opts to arity-3 function" do
      fun = fn _data, _logprobs, opts ->
        {Keyword.get(opts, :custom_value, 0), %{"received" => true}}
      end

      {loss, metrics} = Regularizer.execute(fun, [], [], custom_value: 42)

      assert loss == 42
      assert metrics == %{"received" => true}
    end
  end

  describe "execute/4 with behaviour modules" do
    test "executes module implementing behaviour" do
      data = []
      logprobs = [-1.0, 2.0, -3.0]

      {loss, metrics} = Regularizer.execute(TestL1Regularizer, data, logprobs)

      assert loss == 6.0
      assert metrics["l1_value"] == 6.0
    end

    test "executes module without optional name callback" do
      data = []
      logprobs = [1.0, 2.0, 3.0]

      {loss, metrics} = Regularizer.execute(TestRegWithoutName, data, logprobs)

      assert loss == 2.0
      assert metrics == %{}
    end

    test "passes opts to module compute" do
      defmodule TestWithOpts do
        @behaviour Tinkex.Regularizer

        @impl true
        def compute(_data, logprobs, opts) do
          scale = Keyword.get(opts, :scale, 1.0)
          {Enum.sum(logprobs) * scale, %{"scale" => scale}}
        end
      end

      {loss, metrics} = Regularizer.execute(TestWithOpts, [], [1.0, 2.0], scale: 10.0)

      assert loss == 30.0
      assert metrics["scale"] == 10.0
    end
  end

  describe "behaviour callbacks" do
    test "TestL1Regularizer.name returns expected name" do
      assert TestL1Regularizer.name() == "test_l1"
    end

    test "TestRegWithoutName does not need name callback" do
      # This should compile without name callback since it's optional
      {loss, _} = TestRegWithoutName.compute([], [1.0], [])
      assert loss == 1.0
    end

    test "compute callback receives all arguments" do
      defmodule TestArgsCapture do
        @behaviour Tinkex.Regularizer

        @impl true
        def compute(data, logprobs, opts) do
          # Return info about what we received
          {length(data) + length(logprobs) + length(opts),
           %{
             "data_count" => length(data),
             "logprobs_count" => length(logprobs),
             "opts_count" => length(opts)
           }}
        end
      end

      data = [%{}, %{}]
      logprobs = [1.0, 2.0, 3.0]
      opts = [foo: :bar, baz: :qux]

      {loss, metrics} = TestArgsCapture.compute(data, logprobs, opts)

      assert loss == 7
      assert metrics["data_count"] == 2
      assert metrics["logprobs_count"] == 3
      assert metrics["opts_count"] == 2
    end
  end

  describe "edge cases" do
    test "handles empty logprobs" do
      fun = fn _data, logprobs ->
        if logprobs == [] do
          {0.0, %{"empty" => true}}
        else
          {Enum.sum(logprobs), %{}}
        end
      end

      {loss, metrics} = Regularizer.execute(fun, [], [])

      assert loss == 0.0
      assert metrics == %{"empty" => true}
    end

    test "handles nil data" do
      fun = fn data, _logprobs ->
        {if(is_nil(data), do: 0.0, else: 1.0), %{}}
      end

      {loss, _} = Regularizer.execute(fun, nil, [1.0])

      assert loss == 0.0
    end
  end
end
