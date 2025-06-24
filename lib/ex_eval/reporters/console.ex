defmodule ExEval.Reporters.Console do
  @moduledoc """
  Console reporter for ExEval evaluation results.

  Provides rich, colored output for evaluation progress and results.
  Supports two modes:
  - Default: Minimal dot-based progress (like ExUnit)
  - Trace: Detailed output with reasoning for each test
  """

  @behaviour ExEval.Reporter

  defstruct [:trace, :start_time, :failed_results, :error_results, :results, :printed_headers]

  @impl ExEval.Reporter
  def init(runner, config) do
    state = %__MODULE__{
      trace: config[:trace] || runner.options[:trace] || false,
      start_time: System.monotonic_time(:millisecond),
      failed_results: [],
      error_results: [],
      results: [],
      printed_headers: MapSet.new()
    }

    print_header(runner, state)
    {:ok, state}
  end

  @impl ExEval.Reporter
  def report_result(result, state, _config) do
    if state.trace do
      # Trace mode prints results as they complete, unlike normal mode which batches
      new_state = print_trace_result_with_headers(result, state)

      new_state =
        case result.status do
          :failed -> %{new_state | failed_results: [result | new_state.failed_results]}
          :error -> %{new_state | error_results: [result | new_state.error_results]}
          _ -> new_state
        end

      {:ok, new_state}
    else
      print_dot_result(result)

      new_state =
        case result.status do
          :failed -> %{state | failed_results: [result | state.failed_results]}
          :error -> %{state | error_results: [result | state.error_results]}
          _ -> state
        end

      {:ok, new_state}
    end
  end

  @impl ExEval.Reporter
  def finalize(runner, state, _config) do
    # No need to print trace results in finalize since we print them as we go
    if !state.trace do
      IO.puts("")
    end

    print_summary(runner, state)
    :ok
  end

  defp print_header(runner, _state) do
    total_count =
      runner.modules
      |> Enum.reduce(0, fn dataset, acc ->
        cases = Map.get(dataset, :cases, [])
        acc + Enum.count(cases)
      end)

    IO.puts("Running ExEval with seed: #{:rand.uniform(999_999)}, max_cases: #{total_count}")
    IO.puts("")
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
        IO.puts("#{prefix} #{green("✓")}#{green(duration_str)}")

      :failed ->
        IO.puts("#{prefix} #{red("✗")}#{red(duration_str)}")
        IO.puts("  #{red("Failure:")} #{result.reasoning}")

      :error ->
        IO.puts("#{prefix} #{yellow("!")}#{yellow(duration_str)}")
        IO.puts("  #{yellow("Error:")} #{result.error}")
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

  defp print_summary(runner, state) do
    results_by_status = Enum.group_by(runner.results, & &1.status)
    passed = length(Map.get(results_by_status, :passed, []))
    failed = length(state.failed_results)
    errors = length(state.error_results)

    duration =
      if runner.finished_at && runner.started_at do
        DateTime.diff(runner.finished_at, runner.started_at, :millisecond)
      else
        0
      end

    if !state.trace do
      IO.puts("")
    end

    if failed > 0 && !state.trace do
      IO.puts("")

      state.failed_results
      |> Enum.reverse()
      |> Enum.with_index(1)
      |> Enum.each(fn {result, index} ->
        category_info = if result[:category], do: " [#{result.category}]", else: ""
        IO.puts("  #{index}) #{format_input_for_summary(result.input)}#{category_info}")
        IO.puts("     #{red(result.reasoning)}")
        IO.puts("")
      end)
    end

    if errors > 0 && !state.trace do
      state.error_results
      |> Enum.reverse()
      |> Enum.with_index(failed + 1)
      |> Enum.each(fn {result, index} ->
        category_info = if result[:category], do: " [#{result.category}]", else: ""
        IO.puts("  #{index}) #{format_input_for_summary(result.input)}#{category_info}")
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
