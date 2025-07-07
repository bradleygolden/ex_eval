defmodule ExEval.MetricsTest do
  use ExUnit.Case

  alias ExEval.Metrics

  describe "compute/1" do
    test "handles empty results" do
      metrics = Metrics.compute([])

      assert metrics.total_cases == 0
      assert metrics.passed == 0
      assert metrics.failed == 0
      assert metrics.errors == 0
      assert metrics.pass_rate == 0.0
      assert metrics.avg_latency_ms == 0.0
      assert metrics.p50_latency_ms == 0.0
      assert metrics.p95_latency_ms == 0.0
      assert metrics.p99_latency_ms == 0.0
      assert metrics.by_category == %{}
    end

    test "computes basic metrics correctly" do
      results = [
        %{status: :passed, duration_ms: 100, category: :basic},
        %{status: :failed, duration_ms: 200, category: :basic},
        %{status: :error, duration_ms: 150, category: :advanced},
        %{status: :passed, duration_ms: 300, category: :advanced}
      ]

      metrics = Metrics.compute(results)

      assert metrics.total_cases == 4
      assert metrics.passed == 2
      assert metrics.failed == 1
      assert metrics.errors == 1
      assert metrics.pass_rate == 0.5
      assert metrics.avg_latency_ms == 187.5
    end

    test "handles results without duration" do
      results = [
        %{status: :passed},
        %{status: :failed, duration_ms: nil},
        %{status: :passed, duration_ms: 100}
      ]

      metrics = Metrics.compute(results)

      assert metrics.total_cases == 3
      assert metrics.passed == 2
      assert metrics.failed == 1
      assert metrics.avg_latency_ms == 100.0
      assert metrics.p50_latency_ms == 100.0
    end

    test "calculates percentiles correctly" do
      # Create results with known latencies for easy percentile calculation
      latencies = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

      results =
        Enum.map(latencies, fn latency ->
          %{status: :passed, duration_ms: latency}
        end)

      metrics = Metrics.compute(results)

      assert metrics.avg_latency_ms == 550.0
      # 50th percentile of [100..1000] 
      assert metrics.p50_latency_ms == 600.0
      # 95th percentile
      assert metrics.p95_latency_ms == 1000.0
      # 99th percentile
      assert metrics.p99_latency_ms == 1000.0
    end

    test "groups metrics by category correctly" do
      results = [
        %{status: :passed, category: :safety},
        %{status: :failed, category: :safety},
        %{status: :passed, category: :performance},
        %{status: :passed, category: :performance},
        %{status: :error, category: :performance},
        # No category - should be :uncategorized
        %{status: :passed}
      ]

      metrics = Metrics.compute(results)

      assert metrics.by_category[:safety].total == 2
      assert metrics.by_category[:safety].passed == 1
      assert metrics.by_category[:safety].failed == 1
      assert metrics.by_category[:safety].errors == 0
      assert metrics.by_category[:safety].pass_rate == 0.5

      assert metrics.by_category[:performance].total == 3
      assert metrics.by_category[:performance].passed == 2
      assert metrics.by_category[:performance].failed == 0
      assert metrics.by_category[:performance].errors == 1
      assert metrics.by_category[:performance].pass_rate == 0.667

      assert metrics.by_category[:uncategorized].total == 1
      assert metrics.by_category[:uncategorized].passed == 1
      assert metrics.by_category[:uncategorized].failed == 0
      assert metrics.by_category[:uncategorized].errors == 0
      assert metrics.by_category[:uncategorized].pass_rate == 1.0
    end

    test "handles single result" do
      results = [%{status: :passed, duration_ms: 250, category: :test}]

      metrics = Metrics.compute(results)

      assert metrics.total_cases == 1
      assert metrics.passed == 1
      assert metrics.failed == 0
      assert metrics.errors == 0
      assert metrics.pass_rate == 1.0
      assert metrics.avg_latency_ms == 250.0
      assert metrics.p50_latency_ms == 250.0
      assert metrics.p95_latency_ms == 250.0
      assert metrics.p99_latency_ms == 250.0
    end

    test "handles all failed results" do
      results = [
        %{status: :failed, duration_ms: 100},
        %{status: :error, duration_ms: 200},
        %{status: :failed, duration_ms: 150}
      ]

      metrics = Metrics.compute(results)

      assert metrics.total_cases == 3
      assert metrics.passed == 0
      assert metrics.failed == 2
      assert metrics.errors == 1
      assert metrics.pass_rate == 0.0
    end

    test "handles all passed results" do
      results = [
        %{status: :passed, duration_ms: 100},
        %{status: :passed, duration_ms: 200},
        %{status: :passed, duration_ms: 150}
      ]

      metrics = Metrics.compute(results)

      assert metrics.total_cases == 3
      assert metrics.passed == 3
      assert metrics.failed == 0
      assert metrics.errors == 0
      assert metrics.pass_rate == 1.0
    end

    test "rounds values appropriately" do
      results = [
        %{status: :passed, duration_ms: 33},
        %{status: :failed, duration_ms: 66},
        %{status: :passed, duration_ms: 100}
      ]

      metrics = Metrics.compute(results)

      # 2 passed out of 3 = 0.667 (rounded to 3 decimal places)
      assert metrics.pass_rate == 0.667
      # (33 + 66 + 100) / 3 = 66.33... (rounded to 1 decimal place)
      assert metrics.avg_latency_ms == 66.3
    end

    test "handles unknown status values" do
      results = [
        %{status: :passed, duration_ms: 100},
        %{status: :unknown_status, duration_ms: 200},
        %{status: :failed, duration_ms: 150}
      ]

      metrics = Metrics.compute(results)

      # Unknown status should not be counted in passed, failed, or errors
      assert metrics.total_cases == 3
      assert metrics.passed == 1
      assert metrics.failed == 1
      assert metrics.errors == 0
      # 1 passed out of 3 total
      assert metrics.pass_rate == 0.333
    end

    test "handles mixed data types in duration" do
      results = [
        %{status: :passed, duration_ms: 100},
        %{status: :passed, duration_ms: "not_a_number"},
        %{status: :passed, duration_ms: 200}
      ]

      metrics = Metrics.compute(results)

      # Should ignore non-numeric durations
      assert metrics.avg_latency_ms == 150.0
      assert metrics.p50_latency_ms == 200.0
    end
  end
end
