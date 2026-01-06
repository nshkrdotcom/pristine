defmodule Tinkex.MetricsReductionTest do
  use ExUnit.Case, async: true

  alias Tinkex.MetricsReduction
  alias Tinkex.Types.ForwardBackwardOutput

  describe "reduce/1" do
    test "returns empty map for empty list" do
      assert MetricsReduction.reduce([]) == %{}
    end

    test "returns metrics from single result unchanged" do
      result = %ForwardBackwardOutput{
        loss_fn_output_type: :scalar,
        loss_fn_outputs: [1.0, 2.0],
        metrics: %{"loss:mean" => 1.5}
      }

      reduced = MetricsReduction.reduce([result])
      assert reduced == %{"loss:mean" => 1.5}
    end

    test "reduces sum metrics" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"count:sum" => 10}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"count:sum" => 20}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert reduced["count:sum"] == 30
    end

    test "reduces min metrics" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"loss:min" => 10.0}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"loss:min" => 5.0}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert reduced["loss:min"] == 5.0
    end

    test "reduces max metrics" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"loss:max" => 10.0}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"loss:max" => 15.0}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert reduced["loss:max"] == 15.0
    end

    test "reduces mean metrics with weights" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0, 2.0],
          metrics: %{"loss:mean" => 10.0}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [3.0],
          metrics: %{"loss:mean" => 20.0}
        }
      ]

      # Weight 2 for first (10.0), weight 1 for second (20.0)
      # (10.0 * 2 + 20.0 * 1) / 3 = 40/3 ≈ 13.33
      reduced = MetricsReduction.reduce(results)
      assert_in_delta reduced["loss:mean"], 13.333, 0.01
    end

    test "handles unique metrics by emitting suffixed keys" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"id:unique" => 100}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"id:unique" => 200}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [3.0],
          metrics: %{"id:unique" => 300}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert reduced["id:unique"] == 100
      assert reduced["id:unique_2"] == 200
      assert reduced["id:unique_3"] == 300
    end

    test "hash_unordered returns integer" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"batch:hash_unordered" => 5}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"batch:hash_unordered" => 3}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert is_integer(reduced["batch:hash_unordered"])
    end

    test "unknown suffix defaults to weighted mean" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0, 2.0],
          metrics: %{"custom:unknown" => 10.0}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [3.0],
          metrics: %{"custom:unknown" => 20.0}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      # Same as mean: (10.0 * 2 + 20.0 * 1) / 3 = 40/3
      assert_in_delta reduced["custom:unknown"], 13.333, 0.01
    end

    test "only considers keys from first chunk" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"a:sum" => 10}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"a:sum" => 20, "b:sum" => 100}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert Map.has_key?(reduced, "a:sum")
      refute Map.has_key?(reduced, "b:sum")
    end

    test "ignores missing keys in later chunks" do
      results = [
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [1.0],
          metrics: %{"a:sum" => 10, "b:sum" => 5}
        },
        %ForwardBackwardOutput{
          loss_fn_output_type: :scalar,
          loss_fn_outputs: [2.0],
          metrics: %{"a:sum" => 20}
        }
      ]

      reduced = MetricsReduction.reduce(results)
      assert reduced["a:sum"] == 30
      # b:sum only has one value from first chunk
      assert reduced["b:sum"] == 5
    end
  end
end
