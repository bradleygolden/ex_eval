defmodule ExEval.ConsoleReporter do
  @moduledoc """
  Console reporter for ExEval evaluation results.

  Provides rich, colored output for evaluation progress and results.
  Supports two modes:
  - Default: Minimal dot-based progress (like ExUnit)
  - Trace: Detailed output with reasoning for each test
  """

  @doc """
  Print evaluation run header
  """
  def print_header(%ExEval.Runner{} = runner) do
    total_count =
      runner.modules
      |> Enum.reduce(0, fn dataset, acc ->
        cases = Map.get(dataset, :cases, [])
        acc + Enum.count(cases)
      end)

    IO.puts("Running ExEval with seed: #{:rand.uniform(999_999)}, max_cases: #{total_count}")

    if !runner.options[:trace] || runner.options[:parallel] == false do
      IO.puts("")
    end
  end

  @doc """
  Print progress for a single evaluation result
  """
  def print_result(result, options \\ []) do
    if options[:trace] do
      print_trace_result(result)
    else
      print_dot_result(result)
    end
  end

  defp print_trace_result(result) do
    input_str = format_input_for_trace(result.input)

    test_description =
      if String.length(input_str) > 60 do
        String.slice(input_str, 0, 57) <> "..."
      else
        input_str
      end

    duration_str =
      if result[:duration_ms], do: " (#{format_duration(result.duration_ms)})", else: ""

    case result.status do
      :passed ->
        IO.puts("  * #{test_description}#{green(duration_str)}")

      :failed ->
        IO.puts("  * #{test_description}#{red(duration_str)}")
        IO.puts("")
        IO.puts("     Failure:")
        IO.puts("     #{result.reasoning}")
        IO.puts("")

      :error ->
        IO.puts("  * #{test_description}#{yellow(duration_str)}")
        IO.puts("")
        IO.puts("     Error:")
        IO.puts("     #{result.error}")
        IO.puts("")
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
      :passed -> IO.write(green("."))
      :failed -> IO.write(red("F"))
      :error -> IO.write(yellow("E"))
    end
  end

  @doc """
  Print evaluation result summary
  """
  def print_summary(%ExEval.Runner{} = runner) do
    results_by_status = Enum.group_by(runner.results, & &1.status)
    passed = length(Map.get(results_by_status, :passed, []))
    failed = length(Map.get(results_by_status, :failed, []))
    errors = length(Map.get(results_by_status, :error, []))

    duration =
      if runner.finished_at && runner.started_at do
        DateTime.diff(runner.finished_at, runner.started_at, :millisecond)
      else
        0
      end

    if !runner.options[:trace] do
      IO.puts("")
    end

    if failed > 0 && !runner.options[:trace] do
      IO.puts("")

      results_by_status[:failed]
      |> Enum.with_index(1)
      |> Enum.each(fn {result, index} ->
        IO.puts("  #{index}) #{result.module}: #{format_input_for_summary(result.input)}")
        if result.category, do: IO.puts("     Category: #{result.category}")
        IO.puts("     #{red(result.reasoning)}")
        IO.puts("")
      end)
    end

    if errors > 0 && !runner.options[:trace] do
      results_by_status[:error]
      |> Enum.with_index(failed + 1)
      |> Enum.each(fn {result, index} ->
        IO.puts("  #{index}) #{result.module}: #{format_input_for_summary(result.input)}")
        IO.puts("     #{yellow(result.error)}")
        IO.puts("")
      end)
    end

    IO.puts("Finished in #{format_duration(duration)}")

    total = passed + failed + errors

    if failed == 0 && errors == 0 do
      IO.puts(green("#{total} evaluations, 0 failures"))
    else
      failures_text = if failed == 1, do: "failure", else: "failures"

      errors_text =
        if errors > 0 do
          error_word = if errors == 1, do: "error", else: "errors"
          ", #{errors} #{error_word}"
        else
          ""
        end

      IO.puts("#{total} evaluations, #{red("#{failed} #{failures_text}")}#{errors_text}")
    end

    if failed > 0 || errors > 0 do
      IO.puts("\nRandomized with seed #{:rand.uniform(999_999)}")
    end
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

  defp colorize(text, color) do
    case color do
      :green -> "\e[32m#{text}\e[0m"
      :red -> "\e[31m#{text}\e[0m"
      :yellow -> "\e[33m#{text}\e[0m"
      _ -> text
    end
  end
end
