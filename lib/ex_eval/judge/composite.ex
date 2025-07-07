defmodule ExEval.Judge.Composite do
  @moduledoc """
  Composite judge patterns for consensus, weighted voting, and other
  multi-judge evaluation strategies.

  This module provides several pre-built composite judge patterns:
  - Consensus: Multiple judges must agree
  - Weighted: Weighted voting across judges  
  - Sequential: Run judges in sequence with early termination
  - Hierarchical: Primary judge with fallback judges
  """

  defmodule Consensus do
    @moduledoc """
    Consensus judge that combines results from multiple judges.

    ## Configuration

    - `:judges` - List of judge configurations (required)
    - `:strategy` - How to combine results: `:unanimous`, `:majority`, `:threshold` (default: `:majority`)
    - `:threshold` - For `:threshold` strategy, the minimum agreement ratio (0.0-1.0)
    - `:aggregate_metadata` - Whether to include all judge metadata (default: true)

    ## Examples

        # Majority consensus (at least 50% must agree)
        config = ExEval.new()
        |> ExEval.put_consensus_judge([
          {Judge1, model: "gpt-4"},
          {Judge2, model: "claude-3"},
          Judge3
        ])
        
        # Unanimous consensus (all must agree)
        config = ExEval.new()
        |> ExEval.put_consensus_judge(
          [Judge1, Judge2, Judge3],
          strategy: :unanimous
        )
        
        # Threshold consensus (at least 75% must agree)
        config = ExEval.new()
        |> ExEval.put_consensus_judge(
          [Judge1, Judge2, Judge3, Judge4],
          strategy: :threshold,
          threshold: 0.75
        )
    """
    @behaviour ExEval.Judge

    @impl true
    def call(response, criteria, config) do
      judges = config[:judges]
      strategy = config[:strategy] || :majority

      if judges == nil || judges == [] do
        {:error, "Consensus judge requires non-empty :judges list"}
      else
        call_with_judges(response, criteria, config, judges, strategy)
      end
    end

    defp call_with_judges(response, criteria, config, judges, strategy) do
      # Run all judges in parallel
      results =
        judges
        |> Task.async_stream(
          fn judge_config ->
            run_single_judge(judge_config, response, criteria)
          end,
          timeout: config[:timeout] || 30_000
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, :timeout}
        end)

      # Check for errors
      errors = Enum.filter(results, &match?({:error, _}, &1))

      if length(errors) > 0 do
        {:error, "#{length(errors)} judge(s) failed: #{inspect(errors)}"}
      else
        combine_results(results, strategy, config)
      end
    end

    defp run_single_judge(judge_config, response, criteria) do
      case judge_config do
        {module, opts} when is_atom(module) and is_list(opts) ->
          module.call(response, criteria, Enum.into(opts, %{}))

        module when is_atom(module) ->
          module.call(response, criteria, %{})

        _ ->
          {:error, "Invalid judge configuration: #{inspect(judge_config)}"}
      end
    end

    defp combine_results(results, strategy, config) do
      # Extract successful results
      successful_results =
        results
        |> Enum.filter(&match?({:ok, _, _}, &1))
        |> Enum.map(fn {:ok, result, metadata} -> {result, metadata} end)

      case strategy do
        :unanimous ->
          combine_unanimous(successful_results, config)

        :majority ->
          combine_majority(successful_results, config)

        :threshold ->
          threshold = config[:threshold] || 0.5
          combine_threshold(successful_results, threshold, config)

        _ ->
          {:error, "Unknown consensus strategy: #{strategy}"}
      end
    end

    defp combine_unanimous(results, config) do
      {values, _metadatas} = Enum.unzip(results)

      # For unanimous, all results must be equal
      unique_values = Enum.uniq(values)

      if length(unique_values) == 1 do
        consensus_value = hd(unique_values)
        metadata = build_consensus_metadata(consensus_value, results, :unanimous, config)
        {:ok, consensus_value, metadata}
      else
        # No consensus - return the distribution
        metadata = %{
          consensus: false,
          strategy: :unanimous,
          distribution: Enum.frequencies(values),
          individual_results: if(config[:aggregate_metadata], do: results, else: nil)
        }

        {:ok, :no_consensus, metadata}
      end
    end

    defp combine_majority(results, config) do
      {values, _metadatas} = Enum.unzip(results)

      # Count occurrences of each value
      frequencies = Enum.frequencies(values)
      total = length(values)

      # Find values that appear in more than 50% of results
      majority_threshold = total / 2

      majority_values =
        frequencies
        |> Enum.filter(fn {_value, count} -> count > majority_threshold end)
        |> Enum.map(&elem(&1, 0))

      case majority_values do
        [consensus_value] ->
          metadata = build_consensus_metadata(consensus_value, results, :majority, config)
          {:ok, consensus_value, metadata}

        [] ->
          # No majority - return the most common value
          {most_common, count} = Enum.max_by(frequencies, &elem(&1, 1))

          metadata = %{
            consensus: false,
            strategy: :majority,
            distribution: frequencies,
            most_common: most_common,
            agreement_ratio: count / total,
            individual_results: if(config[:aggregate_metadata], do: results, else: nil),
            reasoning:
              if(config[:aggregate_metadata],
                do: collect_reasoning(results),
                else: "No majority consensus"
              )
          }

          {:ok, most_common, metadata}

        _ ->
          # Multiple values have majority (shouldn't happen)
          {:error, "Multiple values have majority"}
      end
    end

    defp combine_threshold(results, threshold, config) do
      {values, _metadatas} = Enum.unzip(results)

      # Count occurrences of each value
      frequencies = Enum.frequencies(values)
      total = length(values)

      # Find values that meet the threshold
      threshold_values =
        frequencies
        |> Enum.filter(fn {_value, count} -> count / total >= threshold end)
        |> Enum.map(&elem(&1, 0))

      case threshold_values do
        [consensus_value] ->
          metadata =
            build_consensus_metadata(consensus_value, results, {:threshold, threshold}, config)

          {:ok, consensus_value, metadata}

        [] ->
          # No value meets threshold - return the most common
          {most_common, count} = Enum.max_by(frequencies, &elem(&1, 1))

          metadata = %{
            consensus: false,
            strategy: {:threshold, threshold},
            distribution: frequencies,
            most_common: most_common,
            agreement_ratio: count / total,
            individual_results: if(config[:aggregate_metadata], do: results, else: nil)
          }

          {:ok, most_common, metadata}

        multiple ->
          # Multiple values meet threshold - pick the one with highest agreement
          consensus_value =
            multiple
            |> Enum.max_by(&frequencies[&1])

          metadata =
            build_consensus_metadata(consensus_value, results, {:threshold, threshold}, config)

          {:ok, consensus_value, metadata}
      end
    end

    defp build_consensus_metadata(consensus_value, results, strategy, config) do
      {values, metadatas} = Enum.unzip(results)

      agreement_count = Enum.count(values, &(&1 == consensus_value))
      total = length(values)

      base_metadata = %{
        consensus: true,
        strategy: strategy,
        agreement_ratio: agreement_count / total,
        total_judges: total,
        agreeing_judges: agreement_count
      }

      if config[:aggregate_metadata] do
        # Collect reasoning from all judges
        all_reasoning =
          metadatas
          |> Enum.map(&Map.get(&1, :reasoning))
          |> Enum.reject(&is_nil/1)

        Map.merge(base_metadata, %{
          individual_results: results,
          reasoning: "Consensus: #{Enum.join(all_reasoning, " | ")}"
        })
      else
        base_metadata
      end
    end

    defp collect_reasoning(results) do
      results
      |> Enum.map(fn {_value, metadata} -> Map.get(metadata, :reasoning) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")
    end
  end

  defmodule Weighted do
    @moduledoc """
    Weighted voting judge that assigns different weights to different judges.

    ## Configuration

    - `:judges` - List of `{judge_config, weight}` tuples (required)
    - `:aggregation` - How to aggregate weighted results (default: `:weighted_average`)

    ## Examples

        # Weighted voting with explicit weights
        config = ExEval.new()
        |> ExEval.put_weighted_judge([
          {{Judge1, model: "gpt-4"}, 0.5},
          {{Judge2, model: "claude-3"}, 0.3},
          {Judge3, 0.2}
        ])
    """
    @behaviour ExEval.Judge

    @impl true
    def call(response, criteria, config) do
      weighted_judges = config[:judges]

      if weighted_judges == nil || weighted_judges == [] do
        {:error, "Weighted judge requires non-empty :judges list"}
      else
        call_with_weighted_judges(response, criteria, config, weighted_judges)
      end
    end

    defp call_with_weighted_judges(response, criteria, config, weighted_judges) do
      # Validate weights are positive
      invalid_weights = Enum.filter(weighted_judges, fn {_judge, weight} -> weight <= 0 end)

      if invalid_weights != [] do
        {:error, "All weights must be positive numbers"}
      else
        # Normalize weights
        total_weight = weighted_judges |> Enum.map(&elem(&1, 1)) |> Enum.sum()

        normalized_judges =
          Enum.map(weighted_judges, fn {judge_config, weight} ->
            {judge_config, weight / total_weight}
          end)

        # Run all judges in parallel
        results =
          normalized_judges
          |> Task.async_stream(
            fn {judge_config, weight} ->
              case run_single_judge(judge_config, response, criteria) do
                {:ok, result, metadata} -> {:ok, {result, metadata, weight}}
                error -> error
              end
            end,
            timeout: config[:timeout] || 30_000
          )
          |> Enum.map(fn
            {:ok, result} -> result
            {:exit, :timeout} -> {:error, :timeout}
          end)

        # Check for errors
        errors = Enum.filter(results, &match?({:error, _}, &1))

        if length(errors) > 0 do
          {:error, "#{length(errors)} judge(s) failed: #{inspect(errors)}"}
        else
          aggregate_weighted_results(results, config)
        end
      end
    end

    defp run_single_judge(judge_config, response, criteria) do
      case judge_config do
        {module, opts} when is_atom(module) and is_list(opts) ->
          module.call(response, criteria, Enum.into(opts, %{}))

        module when is_atom(module) ->
          module.call(response, criteria, %{})

        _ ->
          {:error, "Invalid judge configuration: #{inspect(judge_config)}"}
      end
    end

    defp aggregate_weighted_results(results, _config) do
      successful_results =
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, weighted_result} -> weighted_result end)

      # Group by result type
      by_type =
        Enum.group_by(successful_results, fn {result, _metadata, _weight} ->
          cond do
            is_boolean(result) -> :boolean
            is_number(result) -> :numeric
            is_atom(result) -> :categorical
            is_map(result) -> :map
            true -> :other
          end
        end)

      # Aggregate based on predominant type
      predominant_type =
        by_type
        |> Enum.map(fn {type, results} ->
          total_weight = results |> Enum.map(&elem(&1, 2)) |> Enum.sum()
          {type, total_weight}
        end)
        |> Enum.max_by(&elem(&1, 1))
        |> elem(0)

      # Filter results to only include the predominant type
      filtered_results = Map.get(by_type, predominant_type, [])

      case predominant_type do
        :boolean -> aggregate_boolean_weighted(filtered_results)
        :numeric -> aggregate_numeric_weighted(filtered_results)
        :categorical -> aggregate_categorical_weighted(filtered_results)
        _ -> aggregate_generic_weighted(filtered_results)
      end
    end

    defp aggregate_boolean_weighted(results) do
      true_weight =
        results
        |> Enum.filter(fn {result, _, _} -> result == true end)
        |> Enum.map(&elem(&1, 2))
        |> Enum.sum()

      total_weight = results |> Enum.map(&elem(&1, 2)) |> Enum.sum()

      weighted_result = true_weight >= total_weight / 2

      metadata = %{
        strategy: :weighted_voting,
        true_weight: Float.round(true_weight, 3),
        false_weight: Float.round(total_weight - true_weight, 3),
        total_weight: Float.round(total_weight, 3),
        individual_results: Enum.map(results, fn {r, m, w} -> {r, m, Float.round(w, 3)} end)
      }

      {:ok, weighted_result, metadata}
    end

    defp aggregate_numeric_weighted(results) do
      weighted_sum =
        results
        |> Enum.map(fn {result, _, weight} -> result * weight end)
        |> Enum.sum()

      metadata = %{
        strategy: :weighted_average,
        individual_results: Enum.map(results, fn {r, m, w} -> {r, m, Float.round(w, 3)} end),
        calculation: :weighted_mean
      }

      {:ok, Float.round(weighted_sum, 3), metadata}
    end

    defp aggregate_categorical_weighted(results) do
      # Sum weights by category
      category_weights =
        results
        |> Enum.reduce(%{}, fn {category, _, weight}, acc ->
          Map.update(acc, category, weight, &(&1 + weight))
        end)

      # Find category with highest weight
      {best_category, best_weight} = Enum.max_by(category_weights, &elem(&1, 1))

      metadata = %{
        strategy: :weighted_voting,
        distribution: category_weights,
        winner_weight: Float.round(best_weight, 3),
        individual_results: Enum.map(results, fn {r, m, w} -> {r, m, Float.round(w, 3)} end)
      }

      {:ok, best_category, metadata}
    end

    defp aggregate_generic_weighted(results) do
      # For other types, return the result with highest weight
      {result, metadata, weight} = Enum.max_by(results, &elem(&1, 2))

      combined_metadata =
        Map.merge(metadata, %{
          strategy: :highest_weight,
          weight: Float.round(weight, 3),
          individual_results: Enum.map(results, fn {r, m, w} -> {r, m, Float.round(w, 3)} end)
        })

      {:ok, result, combined_metadata}
    end
  end
end
