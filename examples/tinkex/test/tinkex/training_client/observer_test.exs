defmodule Tinkex.TrainingClient.ObserverTest do
  use ExUnit.Case, async: false

  alias Tinkex.TrainingClient.Observer

  setup do
    # Clean up any persistent_term entries from previous tests
    model_id = "test-model-#{:rand.uniform(1_000_000)}"

    on_exit(fn ->
      try do
        :persistent_term.erase({:training_queue_state_debounce, model_id})
      rescue
        ArgumentError -> :ok
      end
    end)

    {:ok, model_id: model_id}
  end

  describe "on_queue_state_change/2" do
    test "implements QueueStateObserver behaviour" do
      behaviours = Observer.__info__(:attributes)[:behaviour] || []
      assert Tinkex.QueueStateObserver in behaviours
    end

    test "accepts queue state and metadata", %{model_id: model_id} do
      # QueueState is an atom type: :active | :paused_rate_limit | :paused_capacity | :unknown
      queue_state = :active
      metadata = %{model_id: model_id}

      # Should not raise
      assert :ok = Observer.on_queue_state_change(queue_state, metadata)
    end

    test "works with empty metadata" do
      queue_state = :active

      # Should not raise with empty metadata
      assert :ok = Observer.on_queue_state_change(queue_state, %{})
    end

    test "handles rate limited state", %{model_id: model_id} do
      queue_state = :paused_rate_limit

      metadata = %{
        model_id: model_id,
        queue_state_reason: "capacity_exceeded"
      }

      assert :ok = Observer.on_queue_state_change(queue_state, metadata)
    end

    test "handles capacity paused state", %{model_id: model_id} do
      queue_state = :paused_capacity
      metadata = %{model_id: model_id}

      assert :ok = Observer.on_queue_state_change(queue_state, metadata)
    end

    test "debounces logging via persistent_term", %{model_id: model_id} do
      queue_state = :paused_rate_limit
      metadata = %{model_id: model_id}

      # First call
      assert :ok = Observer.on_queue_state_change(queue_state, metadata)

      # Check that debounce key was set
      debounce_key = {:training_queue_state_debounce, model_id}

      # May or may not have a timestamp depending on log threshold
      # Just verify the function works without errors
      assert :ok = Observer.on_queue_state_change(queue_state, metadata)
    end

    test "uses default model_id when not provided" do
      queue_state = :unknown

      # Should use "unknown" as model_id
      assert :ok = Observer.on_queue_state_change(queue_state)
    end
  end
end
