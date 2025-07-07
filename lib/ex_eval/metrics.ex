defmodule ExEval.Metrics do
  @moduledoc """
  Automatic metrics calculation for evaluation runs.

  Computes standard metrics like pass rate, latency percentiles,
  and category breakdowns from evaluation results.
  """

  @doc """
  Computes comprehensive metrics from evaluation results.

  ## Metrics Included

  - `total_cases` - Total number of evaluation cases
  - `evaluated` - Number of successfully evaluated cases
  - `errors` - Number of error cases
  - `result_distribution` - Distribution of result types and values
  - `avg_latency_ms` - Average evaluation latency
  - `p50_latency_ms` - 50th percentile latency
  - `p95_latency_ms` - 95th percentile latency
  - `p99_latency_ms` - 99th percentile latency
  - `by_category` - Metrics broken down by category

  For backwards compatibility, boolean results are also summarized as:
  - `passed` - Number of true boolean results
  - `failed` - Number of false boolean results
  - `pass_rate` - Percentage of true results (for boolean results only)

  ## Examples

      iex> results = [
      ...>   %{status: :evaluated, result: true, duration_ms: 100},
      ...>   %{status: :evaluated, result: 0.85, duration_ms: 150},
      ...>   %{status: :error, duration_ms: 200}
      ...> ]
      iex> ExEval.Metrics.compute(results)
      %{
        total_cases: 3,
        evaluated: 2,
        errors: 1,
        result_distribution: %{boolean: 1, numeric: 1},
        ...
      }
  """
  def compute(results) when is_list(results) do
    evaluated_results = Enum.filter(results, &(&1.status in [:evaluated, :passed, :failed]))

    base_metrics = %{
      total_cases: length(results),
      evaluated: length(evaluated_results),
      errors: count_by_status(results, :error),
      result_distribution: analyze_result_distribution(evaluated_results),
      avg_latency_ms: calculate_avg_latency(results),
      p50_latency_ms: calculate_percentile(results, 50),
      p95_latency_ms: calculate_percentile(results, 95),
      p99_latency_ms: calculate_percentile(results, 99),
      by_category: group_metrics_by_category(results)
    }

    # Always add boolean metrics (even if 0)
    add_boolean_metrics(base_metrics, results)
  end

  defp count_by_status(results, status) do
    Enum.count(results, &(&1.status == status))
  end

  defp analyze_result_distribution(evaluated_results) do
    evaluated_results
    |> Enum.group_by(fn result_map ->
      # Handle both new format (status: :passed/:failed) and old format (result field)
      cond do
        result_map.status in [:passed, :failed] ->
          :boolean

        Map.has_key?(result_map, :result) ->
          result = result_map.result

          cond do
            is_boolean(result) -> :boolean
            is_number(result) -> :numeric
            is_atom(result) -> :categorical
            is_map(result) -> :multi_dimensional
            true -> :other
          end

        true ->
          :other
      end
    end)
    |> Enum.map(fn {type, results} ->
      case type do
        :boolean ->
          # Count based on status for new format, or result field for old format
          true_count =
            Enum.count(results, fn r ->
              r.status == :passed or (Map.has_key?(r, :result) and r.result == true)
            end)

          false_count =
            Enum.count(results, fn r ->
              r.status == :failed or (Map.has_key?(r, :result) and r.result == false)
            end)

          {type, %{total: length(results), true: true_count, false: false_count}}

        :numeric ->
          values = results |> Enum.filter(&Map.has_key?(&1, :result)) |> Enum.map(& &1.result)

          {type,
           %{
             total: length(results),
             mean: calculate_mean(values),
             min: Enum.min(values, fn -> nil end),
             max: Enum.max(values, fn -> nil end)
           }}

        :categorical ->
          distribution =
            results
            |> Enum.filter(&Map.has_key?(&1, :result))
            |> Enum.frequencies_by(& &1.result)

          {type, %{total: length(results), distribution: distribution}}

        _ ->
          {type, %{total: length(results)}}
      end
    end)
    |> Map.new()
  end

  defp add_boolean_metrics(base_metrics, all_results) do
    # Count passed and failed directly from status
    passed = Enum.count(all_results, &(&1.status == :passed))
    failed = Enum.count(all_results, &(&1.status == :failed))

    # Get total from base_metrics or calculate from results
    total =
      Map.get(base_metrics, :total_cases, Map.get(base_metrics, :total, length(all_results)))

    # Calculate pass rate as passed / total (including errors)
    pass_rate =
      if total > 0 do
        Float.round(passed / total, 3)
      else
        0.0
      end

    Map.merge(base_metrics, %{
      passed: passed,
      failed: failed,
      pass_rate: pass_rate
    })
  end

  defp calculate_mean([]), do: 0.0

  defp calculate_mean(values) do
    sum = Enum.sum(values)
    Float.round(sum / length(values), 3)
  end

  defp calculate_avg_latency([]), do: 0.0

  defp calculate_avg_latency(results) do
    latencies = extract_latencies(results)

    if latencies == [] do
      0.0
    else
      sum = Enum.sum(latencies)
      Float.round(sum / length(latencies), 1)
    end
  end

  defp calculate_percentile([], _percentile), do: 0.0

  defp calculate_percentile(results, percentile) do
    latencies = extract_latencies(results) |> Enum.sort()

    if latencies == [] do
      0.0
    else
      # Use proper percentile calculation (1-based indexing)
      position = percentile / 100.0 * (length(latencies) - 1)
      idx = round(position)
      idx = max(0, min(idx, length(latencies) - 1))
      Enum.at(latencies, idx) || 0.0
    end
  end

  defp extract_latencies(results) do
    results
    |> Enum.map(&Map.get(&1, :duration_ms))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&is_number/1)
  end

  defp group_metrics_by_category(results) do
    results
    |> Enum.group_by(&Map.get(&1, :category, :uncategorized))
    |> Enum.map(fn {category, category_results} ->
      evaluated = Enum.filter(category_results, &(&1.status in [:evaluated, :passed, :failed]))

      category_metrics = %{
        total: length(category_results),
        evaluated: length(evaluated),
        errors: count_by_status(category_results, :error),
        result_distribution: analyze_result_distribution(evaluated)
      }

      # Add boolean metrics if applicable
      category_with_boolean = add_boolean_metrics(category_metrics, category_results)

      {category, category_with_boolean}
    end)
    |> Map.new()
  end
end
