defmodule ExEval.StoreTest do
  use ExUnit.Case

  # Simple in-memory store for testing
  defmodule TestStore do
    @behaviour ExEval.Store
    use Agent

    def start_link(name) do
      Agent.start_link(fn -> %{} end, name: name)
    end

    @impl true
    def save_run(run_data) do
      Agent.update(__MODULE__, fn state ->
        Map.put(state, run_data.id, run_data)
      end)

      :ok
    end

    @impl true
    def get_run(run_id) do
      Agent.get(__MODULE__, fn state ->
        Map.get(state, run_id)
      end)
    end

    @impl true
    def list_runs(opts \\ []) do
      runs = Agent.get(__MODULE__, fn state -> Map.values(state) end)

      case opts[:experiment] do
        nil -> runs
        exp -> Enum.filter(runs, &(get_in(&1, [:metadata, :experiment]) == exp))
      end
    end

    @impl true
    def query(criteria) do
      runs = list_runs()

      # Apply filters
      filtered = apply_filters(runs, criteria)

      # Apply ordering
      ordered = apply_ordering(filtered, criteria[:order_by])

      # Apply limit
      apply_limit(ordered, criteria[:limit])
    end

    defp apply_filters(runs, criteria) do
      runs
      |> filter_by_experiment(criteria[:experiment])
      |> filter_by_tags(criteria[:tags])
      |> filter_by_metrics(criteria[:metrics])
    end

    defp filter_by_experiment(runs, nil), do: runs

    defp filter_by_experiment(runs, experiment) do
      Enum.filter(runs, &(get_in(&1, [:metadata, :experiment]) == experiment))
    end

    defp filter_by_tags(runs, nil), do: runs

    defp filter_by_tags(runs, required_tags) do
      Enum.filter(runs, fn run ->
        run_tags = get_in(run, [:metadata, :tags]) || %{}
        Enum.all?(required_tags, fn {k, v} -> run_tags[k] == v end)
      end)
    end

    defp filter_by_metrics(runs, nil), do: runs

    defp filter_by_metrics(runs, metric_filters) do
      Enum.filter(runs, fn run ->
        metrics = run[:metrics] || %{}

        Enum.all?(metric_filters, fn {metric, [op, value]} ->
          metric_value = metrics[metric]
          apply_comparison(metric_value, op, value)
        end)
      end)
    end

    defp apply_comparison(nil, _, _), do: false
    defp apply_comparison(val, :>, threshold), do: val > threshold
    defp apply_comparison(val, :>=, threshold), do: val >= threshold
    defp apply_comparison(val, :<, threshold), do: val < threshold
    defp apply_comparison(val, :<=, threshold), do: val <= threshold
    defp apply_comparison(val, :==, threshold), do: val == threshold
    defp apply_comparison(val, ">", threshold), do: val > threshold
    defp apply_comparison(val, ">=", threshold), do: val >= threshold
    defp apply_comparison(val, "<", threshold), do: val < threshold
    defp apply_comparison(val, "<=", threshold), do: val <= threshold
    defp apply_comparison(val, "==", threshold), do: val == threshold

    defp apply_ordering(runs, nil), do: runs

    defp apply_ordering(runs, {:metrics, metric, direction}) do
      Enum.sort_by(runs, &(&1[:metrics][metric] || 0), direction)
    end

    defp apply_limit(runs, nil), do: runs
    defp apply_limit(runs, limit), do: Enum.take(runs, limit)
  end

  setup do
    # Start a fresh test store for each test
    start_supervised!({TestStore, TestStore})
    :ok
  end

  describe "save_run/1 and get_run/1" do
    test "saves and retrieves a run" do
      run_data = %{
        id: "test-run-123",
        status: :completed,
        metadata: %{experiment: :test_exp},
        results: []
      }

      assert :ok = TestStore.save_run(run_data)
      assert TestStore.get_run("test-run-123") == run_data
    end

    test "returns nil for non-existent run" do
      assert TestStore.get_run("non-existent") == nil
    end
  end

  describe "list_runs/1" do
    test "lists all runs when no filter" do
      run1 = %{id: "run1", metadata: %{experiment: :exp1}}
      run2 = %{id: "run2", metadata: %{experiment: :exp2}}

      TestStore.save_run(run1)
      TestStore.save_run(run2)

      runs = TestStore.list_runs()
      assert length(runs) == 2
      assert run1 in runs
      assert run2 in runs
    end

    test "filters by experiment" do
      run1 = %{id: "run1", metadata: %{experiment: :exp1}}
      run2 = %{id: "run2", metadata: %{experiment: :exp2}}
      run3 = %{id: "run3", metadata: %{experiment: :exp1}}

      TestStore.save_run(run1)
      TestStore.save_run(run2)
      TestStore.save_run(run3)

      runs = TestStore.list_runs(experiment: :exp1)
      assert length(runs) == 2
      assert run1 in runs
      assert run3 in runs
      refute run2 in runs
    end
  end

  describe "query/1" do
    setup do
      # Create test runs with different metrics
      runs = [
        %{
          id: "run1",
          metadata: %{experiment: :safety_v1, tags: %{environment: :test}},
          metrics: %{pass_rate: 0.80, avg_duration: 100}
        },
        %{
          id: "run2",
          metadata: %{experiment: :safety_v2, tags: %{environment: :production}},
          metrics: %{pass_rate: 0.95, avg_duration: 120}
        },
        %{
          id: "run3",
          metadata: %{experiment: :safety_v2, tags: %{environment: :test}},
          metrics: %{pass_rate: 0.98, avg_duration: 90}
        },
        %{
          id: "run4",
          metadata: %{experiment: :safety_v2, tags: %{environment: :production}},
          metrics: %{pass_rate: 0.92, avg_duration: 110}
        }
      ]

      Enum.each(runs, &TestStore.save_run/1)
      {:ok, runs: runs}
    end

    test "filters by experiment" do
      results = TestStore.query(%{experiment: :safety_v2})
      assert length(results) == 3
      assert Enum.all?(results, &(&1.metadata.experiment == :safety_v2))
    end

    test "filters by tags" do
      results = TestStore.query(%{tags: %{environment: :production}})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metadata.tags.environment == :production))
    end

    test "filters by metrics with > operator" do
      results = TestStore.query(%{metrics: [pass_rate: [:>, 0.93]]})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metrics.pass_rate > 0.93))
    end

    test "filters by metrics with >= operator" do
      results = TestStore.query(%{metrics: [pass_rate: [:>=, 0.95]]})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metrics.pass_rate >= 0.95))
    end

    test "filters by metrics with < operator" do
      results = TestStore.query(%{metrics: [avg_duration: [:<, 105]]})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metrics.avg_duration < 105))
    end

    test "filters by metrics with <= operator" do
      results = TestStore.query(%{metrics: [avg_duration: [:<=, 100]]})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metrics.avg_duration <= 100))
    end

    test "filters by metrics with == operator" do
      results = TestStore.query(%{metrics: [pass_rate: [:==, 0.95]]})
      assert length(results) == 1
      assert List.first(results).id == "run2"
    end

    test "filters by metrics with string operators for backward compatibility" do
      results = TestStore.query(%{metrics: [pass_rate: [">", 0.93]]})
      assert length(results) == 2
      assert Enum.all?(results, &(&1.metrics.pass_rate > 0.93))
    end

    test "orders by metrics descending" do
      results = TestStore.query(%{order_by: {:metrics, :pass_rate, :desc}})
      pass_rates = Enum.map(results, & &1.metrics.pass_rate)
      assert pass_rates == [0.98, 0.95, 0.92, 0.80]
    end

    test "orders by metrics ascending" do
      results = TestStore.query(%{order_by: {:metrics, :avg_duration, :asc}})
      durations = Enum.map(results, & &1.metrics.avg_duration)
      assert durations == [90, 100, 110, 120]
    end

    test "applies limit" do
      results =
        TestStore.query(%{
          order_by: {:metrics, :pass_rate, :desc},
          limit: 2
        })

      assert length(results) == 2
      assert List.first(results).metrics.pass_rate == 0.98
    end

    test "combines multiple filters" do
      results =
        TestStore.query(%{
          experiment: :safety_v2,
          tags: %{environment: :production},
          metrics: [pass_rate: [:>, 0.90]],
          order_by: {:metrics, :pass_rate, :desc},
          limit: 5
        })

      assert length(results) == 2
      assert List.first(results).id == "run2"
      assert List.last(results).id == "run4"
    end

    test "handles runs without metrics gracefully" do
      run_without_metrics = %{
        id: "run5",
        metadata: %{experiment: :test}
        # No metrics field
      }

      TestStore.save_run(run_without_metrics)

      # Should not crash when filtering by metrics
      results = TestStore.query(%{metrics: [pass_rate: [:>, 0.5]]})
      refute Enum.any?(results, &(&1.id == "run5"))

      # Should handle ordering with missing metrics (defaults to 0)
      results = TestStore.query(%{order_by: {:metrics, :pass_rate, :asc}})
      assert List.first(results).id == "run5"
    end

    test "handles empty query criteria" do
      results = TestStore.query(%{})
      assert length(results) == 4
    end
  end
end
