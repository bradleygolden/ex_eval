defmodule ExEval.Reporter.Console do
  @moduledoc """
  Console reporter for ExEval evaluation results.

  Provides rich, colored output for evaluation progress and results.
  Supports two modes:
  - Default: Minimal dot-based progress (like ExUnit)
  - Trace: Detailed output with reasoning for each test
  """

  @behaviour ExEval.Reporter

  defstruct [:trace, :start_time, :printed_headers]

  @impl ExEval.Reporter
  def init(runner, config) do
    state = %__MODULE__{
      trace: config[:trace] || runner.options[:trace] || false,
      start_time: System.monotonic_time(:millisecond),
      printed_headers: MapSet.new()
    }

    print_header(runner, state)
    {:ok, state}
  end

  @impl ExEval.Reporter
  def report_result(result, state, _config) do
    if state.trace do
      # Trace mode prints results as they complete, unlike normal mode which batches
      print_trace_result_with_headers(result, state)
    else
      print_dot_result(result)
    end

    # In the new system, we don't track failed_results separately
    # All results are stored and can be analyzed later
    {:ok, state}
  end

  @impl ExEval.Reporter
  def finalize(runner, state, _config) do
    # Print newline after dots only if we printed any
    if !state.trace && length(runner.results) > 0 do
      IO.puts("")
    end

    print_summary(runner, state)
    :ok
  end

  defp print_header(runner, _state) do
    total_cases =
      Enum.reduce(runner.datasets, 0, fn dataset, acc ->
        acc + length(ExEval.Dataset.cases(dataset))
      end)

    seed = :rand.uniform(999_999)
    IO.puts("Running ExEval with seed: #{seed}, max_cases: #{total_cases}")
    :ok
  end

  defp print_trace_result_with_headers(result, state) do
    print_trace_result_inline(result)
    state
  end

  defp print_trace_result_inline(result) do
    module_name =
      case result[:module] do
        nil -> "Unknown"
        mod -> mod |> Module.split() |> List.last()
      end

    category = result[:category] || "uncategorized"
    input_str = format_input_for_trace(result.input)

    test_description =
      if String.length(input_str) > 40 do
        String.slice(input_str, 0, 37) <> "..."
      else
        input_str
      end

    duration_str =
      if result[:duration_ms], do: " (#{format_duration(result.duration_ms)})", else: ""

    prefix = "#{module_name} [#{category}] #{test_description}"

    case result.status do
      :passed ->
        IO.puts("#{prefix} #{green("✓")}#{duration_str}")
        if result[:reasoning], do: IO.puts("  #{result.reasoning}")

      :failed ->
        IO.puts("#{prefix} #{red("✗")}#{duration_str}")
        if result[:reasoning], do: IO.puts("  #{result.reasoning}")

      :evaluated ->
        # Display based on result type
        result_display = format_result_display(result.result)
        metadata_str = format_metadata(result.metadata)
        IO.puts("#{prefix} #{result_display}#{duration_str}")
        if metadata_str != "", do: IO.puts("  #{metadata_str}")

      :error ->
        IO.puts("#{prefix} #{yellow("!")}#{yellow(duration_str)}")
        IO.puts("  #{yellow("Error:")} #{result.error}")
    end
  end

  defp format_result_display(result) do
    case result do
      true -> green("✓")
      false -> red("✗")
      score when is_number(score) -> format_score(score)
      atom when is_atom(atom) -> format_atom_result(atom)
      map when is_map(map) -> format_map_result(map)
      _ -> cyan(inspect(result))
    end
  end

  defp format_score(score) when score >= 0.8, do: green("#{Float.round(score, 2)}")
  defp format_score(score) when score >= 0.6, do: yellow("#{Float.round(score, 2)}")
  defp format_score(score), do: red("#{Float.round(score, 2)}")

  defp format_atom_result(atom) do
    case atom do
      :excellent -> green("★★★★★")
      :good -> green("★★★★")
      :fair -> yellow("★★★")
      :poor -> red("★★")
      :terrible -> red("★")
      _ -> cyan(":#{atom}")
    end
  end

  defp format_map_result(map) do
    # For multi-dimensional results, show a compact summary
    parts =
      map
      # Limit to first 3 dimensions for display
      |> Enum.take(3)
      |> Enum.map(fn {k, v} -> "#{k}:#{format_dimension_value(v)}" end)
      |> Enum.join(" ")

    cyan("[#{parts}]")
  end

  defp format_dimension_value(v) when is_number(v), do: Float.round(v, 2)
  defp format_dimension_value(v), do: inspect(v)

  defp format_metadata(metadata) do
    # Extract commonly used metadata fields
    if metadata[:reasoning] do
      metadata.reasoning
    else
      # Show other metadata fields
      metadata
      |> Enum.take(2)
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> Enum.join(", ")
    end
  end

  defp format_input_for_trace(input) when is_list(input) do
    List.last(input) || "Multi-turn conversation"
  end

  defp format_input_for_trace(input) when is_binary(input) do
    input
  end

  defp format_input_for_trace(input), do: inspect(input)

  defp print_dot_result(result) do
    case result.status do
      :passed ->
        IO.write(green("."))

      :failed ->
        IO.write(red("F"))

      :evaluated ->
        # For dot output, simplify to a single character based on result type
        case result.result do
          true -> IO.write(green("."))
          false -> IO.write(red("F"))
          score when is_number(score) and score >= 0.8 -> IO.write(green("."))
          score when is_number(score) and score >= 0.6 -> IO.write(yellow("~"))
          score when is_number(score) -> IO.write(red("F"))
          :excellent -> IO.write(green("."))
          :good -> IO.write(green("."))
          :fair -> IO.write(yellow("~"))
          :poor -> IO.write(red("F"))
          :terrible -> IO.write(red("F"))
          _ -> IO.write(cyan("?"))
        end

      :error ->
        IO.write(yellow("E"))
    end
  end

  defp print_summary(runner, state) do
    results_by_status = Enum.group_by(runner.results, & &1.status)
    evaluated_results = Map.get(results_by_status, :evaluated, [])
    passed_results = Map.get(results_by_status, :passed, [])
    failed_results = Map.get(results_by_status, :failed, [])
    error_results = Map.get(results_by_status, :error, [])

    # Combine all non-error results for summarization
    all_evaluated = evaluated_results ++ passed_results ++ failed_results

    duration =
      if runner.finished_at && runner.started_at do
        DateTime.diff(runner.finished_at, runner.started_at, :millisecond)
      else
        0
      end

    # Print failures if any (similar to ExUnit format)
    if length(failed_results) > 0 && !state.trace do
      IO.puts("")
      IO.puts("Failures:")

      failed_results
      |> Enum.with_index(1)
      |> Enum.each(fn {result, index} ->
        category_info = if result[:category], do: " [#{result.category}]", else: ""
        IO.puts("  #{index}) #{format_input_for_summary(result.input)}#{category_info}")
        if result[:reasoning], do: IO.puts("     #{red(result.reasoning)}")
        if index < length(failed_results), do: IO.puts("")
      end)
    end

    # Print errors if any (similar to ExUnit format)
    if length(error_results) > 0 && !state.trace do
      IO.puts("")
      IO.puts("Errors:")

      error_results
      |> Enum.with_index(1)
      |> Enum.each(fn {result, index} ->
        category_info = if result[:category], do: " [#{result.category}]", else: ""
        IO.puts("  #{index}) #{format_input_for_summary(result.input)}#{category_info}")
        IO.puts("     #{yellow(result.error)}")
        if index < length(error_results), do: IO.puts("")
      end)
    end

    # Add blank line before summary
    IO.puts("")
    IO.puts("Finished in #{format_duration(duration)}")

    total = length(runner.results)
    failures = length(failed_results)
    errors = length(error_results)

    # Show result distribution
    result_summary = summarize_results(all_evaluated)

    cond do
      errors > 0 && failures > 0 ->
        failures_text = if failures == 1, do: "failure", else: "failures"
        errors_text = if errors == 1, do: "error", else: "errors"

        IO.puts(
          "#{total} evaluations#{result_summary}, #{red("#{failures} #{failures_text}")}, #{yellow("#{errors} #{errors_text}")}"
        )

      errors > 0 ->
        errors_text = if errors == 1, do: "error", else: "errors"
        IO.puts("#{total} evaluations#{result_summary}, #{yellow("#{errors} #{errors_text}")}")

      failures > 0 ->
        failures_text = if failures == 1, do: "failure", else: "failures"
        IO.puts("#{total} evaluations#{result_summary}, #{red("#{failures} #{failures_text}")}")

      true ->
        IO.puts("#{total} evaluations#{result_summary}")
    end

    # Always print seed like ExUnit does
    IO.puts("\nRandomized with seed #{:rand.uniform(999_999)}")
  end

  defp format_input_for_summary(input) when is_list(input) do
    List.last(input) || "Multi-turn conversation"
  end

  defp format_input_for_summary(input) when is_binary(input) do
    if String.length(input) > 60 do
      String.slice(input, 0, 57) <> "..."
    else
      input
    end
  end

  defp format_input_for_summary(input), do: inspect(input)

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    decimal = rem(ms, 1000) |> div(100)
    "#{seconds}.#{decimal}s"
  end

  defp green(text), do: colorize(text, :green)
  defp red(text), do: colorize(text, :red)
  defp yellow(text), do: colorize(text, :yellow)
  defp cyan(text), do: colorize(text, :cyan)

  defp colorize(text, color) do
    case color do
      :green -> "\e[32m#{text}\e[0m"
      :red -> "\e[31m#{text}\e[0m"
      :yellow -> "\e[33m#{text}\e[0m"
      :cyan -> "\e[36m#{text}\e[0m"
      _ -> text
    end
  end

  defp summarize_results(evaluated_results) do
    # Group results by type and provide a summary
    result_types =
      evaluated_results
      |> Enum.group_by(fn result_map ->
        cond do
          result_map.status in [:passed, :failed] ->
            :boolean

          Map.has_key?(result_map, :result) ->
            result = result_map.result

            cond do
              is_boolean(result) -> :boolean
              is_number(result) -> :score
              is_atom(result) -> :category
              is_map(result) -> :multi_dimensional
              true -> :other
            end

          true ->
            :other
        end
      end)

    summaries = []

    # Boolean results
    summaries =
      if booleans = result_types[:boolean] do
        passed =
          Enum.count(booleans, fn r ->
            r.status == :passed or (Map.has_key?(r, :result) and r.result == true)
          end)

        failed =
          Enum.count(booleans, fn r ->
            r.status == :failed or (Map.has_key?(r, :result) and r.result == false)
          end)

        summaries ++ [format_boolean_summary(passed, failed)]
      else
        summaries
      end

    # Score results
    summaries =
      if scores = result_types[:score] do
        score_values = scores |> Enum.filter(&Map.has_key?(&1, :result)) |> Enum.map(& &1.result)

        if length(score_values) > 0 do
          avg = Enum.sum(score_values) / length(score_values)
          summaries ++ ["avg score: #{Float.round(avg, 2)}"]
        else
          summaries
        end
      else
        summaries
      end

    # Category results
    summaries =
      if categories = result_types[:category] do
        distribution =
          categories
          |> Enum.filter(&Map.has_key?(&1, :result))
          |> Enum.frequencies_by(& &1.result)

        if map_size(distribution) > 0 do
          summaries ++ [format_category_distribution(distribution)]
        else
          summaries
        end
      else
        summaries
      end

    if summaries == [] do
      ""
    else
      " (" <> Enum.join(summaries, ", ") <> ")"
    end
  end

  defp format_boolean_summary(passed, 0), do: green("#{passed} passed")
  defp format_boolean_summary(0, failed), do: red("#{failed} failed")

  defp format_boolean_summary(passed, failed) do
    "#{green("#{passed} passed")}, #{red("#{failed} failed")}"
  end

  defp format_category_distribution(distribution) do
    distribution
    |> Enum.map(fn {category, count} -> "#{category}: #{count}" end)
    |> Enum.join(", ")
  end
end
