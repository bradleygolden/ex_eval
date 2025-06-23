defmodule ExEval.Runner do
  @moduledoc """
  Runner for ExEval evaluation suites.

  This runner is designed specifically for AI evaluations
  with support for:
  - Parallel execution with rate limiting
  - Rich progress reporting
  - Categorized results
  - LLM-as-judge evaluation patterns
  """

  defstruct [
    :modules,
    :options,
    results: [],
    started_at: nil,
    finished_at: nil
  ]

  @doc """
  Runs evaluation modules and returns results.

  ## Options
  - `:parallel` - Run evaluations in parallel (default: true)
  - `:max_concurrency` - Maximum concurrent evaluations (default: 5)
  - `:timeout` - Timeout per evaluation in ms (default: 120_000)
  - `:categories` - Filter by specific categories
  - `:reporter` - Module to handle result reporting
  """
  def run(modules, opts \\ []) when is_list(modules) do
    runner = %__MODULE__{
      modules: modules,
      options: Keyword.merge(default_options(), opts),
      started_at: DateTime.utc_now()
    }

    if reporter = runner.options[:reporter] do
      reporter.print_header(runner)
    end

    results =
      if runner.options[:parallel] do
        run_parallel(runner)
      else
        run_sequential(runner)
      end

    runner = %{runner | results: results, finished_at: DateTime.utc_now()}

    if reporter = runner.options[:reporter] do
      reporter.print_summary(runner)
    end

    runner
  end

  defp default_options do
    [
      parallel: true,
      max_concurrency: 5,
      timeout: 120_000,
      reporter: ExEval.ConsoleReporter
    ]
  end

  defp run_parallel(runner) do
    all_cases =
      runner.modules
      |> Enum.flat_map(fn module ->
        if function_exported?(module, :__ex_eval_eval_cases__, 0) do
          context =
            if function_exported?(module, :__ex_eval_setup__, 0) do
              module.__ex_eval_setup__()
            else
              %{}
            end

          eval_cases = module.__ex_eval_eval_cases__()
          response_fn = module.__ex_eval_response_fn__()

          if runner.options[:trace] do
            IO.puts("\n\n#{inspect(module)}")
          end

          eval_cases
          |> filter_by_categories(runner.options[:categories])
          |> Enum.map(fn eval_case ->
            {module, eval_case, response_fn, context, runner}
          end)
        else
          []
        end
      end)

    all_cases
    |> Task.async_stream(
      fn {module, eval_case, response_fn, context, runner} ->
        Process.put(:eval_context, context)
        result = run_eval_case(eval_case, response_fn, module, runner)
        
        if reporter = runner.options[:reporter] do
          reporter.print_result(result, runner.options)
        end
        
        result
      end,
      max_concurrency: runner.options[:max_concurrency],
      timeout: runner.options[:timeout]
    )
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, {:timeout, _}} ->
        result = %{
          status: :error,
          error: "Evaluation timed out after #{runner.options[:timeout]}ms",
          module: :unknown
        }
        
        if reporter = runner.options[:reporter] do
          reporter.print_result(result, runner.options)
        end
        
        result

      {:exit, reason} ->
        result = %{status: :error, error: "Evaluation crashed: #{inspect(reason)}", module: :unknown}
        
        if reporter = runner.options[:reporter] do
          reporter.print_result(result, runner.options)
        end
        
        result
    end)
  end

  defp run_sequential(runner) do
    runner.modules
    |> Enum.flat_map(fn module ->
      if function_exported?(module, :__ex_eval_eval_cases__, 0) do
        context =
          if function_exported?(module, :__ex_eval_setup__, 0) do
            module.__ex_eval_setup__()
          else
            %{}
          end

        Process.put(:eval_context, context)

        eval_cases = module.__ex_eval_eval_cases__()
        response_fn = module.__ex_eval_response_fn__()

        if runner.options[:trace] do
          IO.puts("\n\n#{inspect(module)}")
        end

        eval_cases
        |> filter_by_categories(runner.options[:categories])
        |> Enum.map(fn eval_case ->
          result = run_eval_case(eval_case, response_fn, module, runner)
          
          if reporter = runner.options[:reporter] do
            reporter.print_result(result, runner.options)
          end
          
          result
        end)
      else
        []
      end
    end)
  end

  defp filter_by_categories(eval_cases, nil), do: eval_cases
  defp filter_by_categories(eval_cases, []), do: eval_cases

  defp filter_by_categories(eval_cases, categories) do
    Enum.filter(eval_cases, fn case_data ->
      Map.get(case_data, :category) in categories
    end)
  end

  defp run_eval_case(eval_case, response_fn, module, _runner) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        Process.put(:ex_eval_conversation_responses, [])

        {response, judge_prompt} =
          try do
            case Map.get(eval_case, :input) do
              inputs when is_list(inputs) ->
                responses =
                  Enum.map(inputs, fn input ->
                    resp = apply_response_fn(response_fn, input)

                    Process.put(
                      :ex_eval_conversation_responses,
                      Process.get(:ex_eval_conversation_responses, []) ++ [resp]
                    )

                    resp
                  end)

                {List.last(responses), Map.get(eval_case, :judge_prompt)}

              input ->
                {apply_response_fn(response_fn, input), Map.get(eval_case, :judge_prompt)}
            end
          rescue
            _e in FunctionClauseError ->
              reraise "FunctionClauseError calling response_fn. Check that response function has correct arity.",
                      __STACKTRACE__
          end

        adapter =
          if function_exported?(module, :__ex_eval_adapter__, 0) do
            module.__ex_eval_adapter__()
          else
            ExEval.Adapters.LangChain
          end

        config =
          if function_exported?(module, :__ex_eval_config__, 0) do
            module.__ex_eval_config__()
          else
            %{}
          end

        judge_result =
          ExEval.Judge.evaluate(
            ExEval.new(adapter: adapter, config: config),
            response,
            judge_prompt
          )

        case judge_result do
          {:ok, true, reasoning} ->
            %{
              status: :passed,
              reasoning: reasoning
            }

          {:ok, false, reasoning} ->
            %{
              status: :failed,
              reasoning: reasoning,
              response: response
            }

          {:error, error} ->
            %{
              status: :error,
              error: "Judge error: #{inspect(error)}"
            }
        end
      catch
        kind, error ->
          %{
            status: :error,
            error:
              "Evaluation crashed: #{kind} #{inspect(error)}\nStacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}"
          }
      end

    end_time = System.monotonic_time(:millisecond)

    Map.merge(result, %{
      module: module,
      category: Map.get(eval_case, :category),
      input: eval_case.input,
      judge_prompt: eval_case.judge_prompt,
      duration_ms: end_time - start_time
    })
  end

  defp apply_response_fn(response_fn, input) do
    try do
      case :erlang.fun_info(response_fn)[:arity] do
        1 ->
          response_fn.(input)

        2 ->
          context = Process.get(:eval_context, %{})
          response_fn.(input, context)

        arity ->
          raise "response_fn has arity #{arity}, must be 1 or 2"
      end
    rescue
      e ->
        reraise e, __STACKTRACE__
    end
  end
end
