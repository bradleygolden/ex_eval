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

  @default_timeout 120_000
  @default_max_concurrency 5

  defstruct [
    :id,
    :datasets,
    :options,
    :metadata,
    results: [],
    started_at: nil,
    finished_at: nil
  ]

  @doc """
  Runs evaluation modules and returns results.

  ## Options
  - `:parallel` - Run evaluations in parallel (default: true)
  - `:max_concurrency` - Maximum concurrent evaluations (default: #{@default_max_concurrency})
  - `:timeout` - Timeout per evaluation in ms (default: #{@default_timeout})
  - `:categories` - Filter by specific categories
  - `:reporter` - Reporter module (default: ExEval.Reporters.Console)
  - `:reporter_config` - Configuration for the reporter
  - `:metadata` - Custom metadata to attach to the run
  """
  def run(items, opts \\ []) when is_list(items) do
    datasets = Enum.map(items, &normalize_to_dataset/1)

    runner = %__MODULE__{
      id: generate_run_id(),
      datasets: datasets,
      options: Keyword.merge(default_options(), opts),
      metadata: Keyword.get(opts, :metadata, %{}),
      started_at: DateTime.utc_now()
    }

    reporter_module = runner.options[:reporter]
    reporter_config = runner.options[:reporter_config] || %{}

    {:ok, reporter_state} = reporter_module.init(runner, reporter_config)

    {results, final_reporter_state} =
      if runner.options[:parallel] do
        run_parallel(runner, reporter_module, reporter_state, reporter_config)
      else
        run_sequential(runner, reporter_module, reporter_state, reporter_config)
      end

    runner = %{runner | results: results, finished_at: DateTime.utc_now()}

    reporter_module.finalize(runner, final_reporter_state, reporter_config)

    runner
  end

  defp default_options do
    [
      parallel: true,
      max_concurrency: @default_max_concurrency,
      timeout: @default_timeout,
      reporter: ExEval.Reporters.Console
    ]
  end

  defp normalize_to_dataset(%{cases: _, response_fn: _} = dataset) do
    dataset
  end

  defp normalize_to_dataset(module) when is_atom(module) do
    ExEval.DatasetProvider.Module.load(module: module)
  end

  defp run_parallel(runner, reporter_module, reporter_state, reporter_config) do
    all_cases = prepare_all_cases(runner)

    {results, final_state} =
      all_cases
      |> run_cases_async(runner)
      |> process_async_results(runner, reporter_module, reporter_state, reporter_config)

    {Enum.reverse(results), final_state}
  end

  defp prepare_all_cases(runner) do
    runner.datasets
    |> Enum.flat_map(fn dataset ->
      context = get_dataset_context(dataset)
      eval_cases = dataset.cases
      response_fn = dataset.response_fn

      eval_cases
      |> filter_by_categories(runner.options[:categories])
      |> Enum.map(fn eval_case ->
        {dataset, eval_case, response_fn, context}
      end)
    end)
  end

  defp get_dataset_context(dataset) do
    if dataset.setup_fn do
      dataset.setup_fn.()
    else
      %{}
    end
  end

  defp run_cases_async(cases, runner) do
    Task.async_stream(
      cases,
      fn {dataset, eval_case, response_fn, context} ->
        run_eval_case(eval_case, response_fn, dataset, context, runner)
      end,
      max_concurrency: runner.options[:max_concurrency],
      timeout: runner.options[:timeout]
    )
  end

  defp process_async_results(stream, runner, reporter_module, reporter_state, reporter_config) do
    Enum.reduce(stream, {[], reporter_state}, fn stream_result, {results_acc, state_acc} ->
      result = handle_stream_result(stream_result, runner)
      {:ok, new_state} = reporter_module.report_result(result, state_acc, reporter_config)
      {[result | results_acc], new_state}
    end)
  end

  defp handle_stream_result(stream_result, runner) do
    case stream_result do
      {:ok, result} ->
        result

      {:exit, {:timeout, _}} ->
        %{
          status: :error,
          error: "Evaluation timed out after #{runner.options[:timeout]}ms"
        }

      {:exit, reason} ->
        %{
          status: :error,
          error: "Evaluation crashed: #{inspect(reason)}"
        }
    end
  end

  defp run_sequential(runner, reporter_module, reporter_state, reporter_config) do
    {results, final_state} =
      runner.datasets
      |> Enum.reduce({[], reporter_state}, fn dataset, {results_acc, state_acc} ->
        context =
          if dataset.setup_fn do
            dataset.setup_fn.()
          else
            %{}
          end

        eval_cases = dataset.cases
        response_fn = dataset.response_fn

        {dataset_results, new_state} =
          eval_cases
          |> filter_by_categories(runner.options[:categories])
          |> Enum.reduce({[], state_acc}, fn eval_case, {case_results, state} ->
            result = run_eval_case(eval_case, response_fn, dataset, context, runner)
            {:ok, updated_state} = reporter_module.report_result(result, state, reporter_config)
            {[result | case_results], updated_state}
          end)

        {results_acc ++ Enum.reverse(dataset_results), new_state}
      end)

    {results, final_state}
  end

  defp filter_by_categories(eval_cases, nil), do: eval_cases
  defp filter_by_categories(eval_cases, []), do: eval_cases

  defp filter_by_categories(eval_cases, categories) do
    Enum.filter(eval_cases, fn case_data ->
      Map.get(case_data, :category) in categories
    end)
  end

  defp run_eval_case(eval_case, response_fn, dataset, context, _runner) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        {response, judge_prompt} = get_response_and_prompt(eval_case, response_fn, context)
        judge_result = run_judge(dataset, response, judge_prompt)
        format_judge_result(judge_result, response)
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
      dataset: dataset,
      module: get_module_from_dataset(dataset),
      category: Map.get(eval_case, :category),
      input: eval_case.input,
      judge_prompt: eval_case.judge_prompt,
      duration_ms: end_time - start_time
    })
  end

  defp get_response_and_prompt(eval_case, response_fn, context) do
    case Map.get(eval_case, :input) do
      inputs when is_list(inputs) ->
        responses = run_conversation(inputs, response_fn, context)
        {List.last(responses), Map.get(eval_case, :judge_prompt)}

      input ->
        {apply_response_fn(response_fn, input, context, []), Map.get(eval_case, :judge_prompt)}
    end
  end

  defp run_conversation(inputs, response_fn, context) do
    {responses, _} =
      Enum.map_reduce(inputs, [], fn input, conversation_history ->
        resp = apply_response_fn(response_fn, input, context, conversation_history)
        {resp, conversation_history ++ [resp]}
      end)

    responses
  end

  defp run_judge(dataset, response, judge_prompt) do
    adapter = Map.get(dataset, :judge_provider) || ExEval.JudgeProvider.LangChain
    config = Map.get(dataset, :config) || %{}

    ExEval.Judge.evaluate(
      ExEval.new(judge_provider: adapter, config: config),
      response,
      judge_prompt
    )
  end

  defp format_judge_result(judge_result, response) do
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
  end

  defp get_module_from_dataset(%{metadata: %{module: module}}), do: module
  defp get_module_from_dataset(_), do: nil

  defp generate_run_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp apply_response_fn(response_fn, input, context, conversation_history) do
    arity = :erlang.fun_info(response_fn)[:arity]

    try do
      case arity do
        1 ->
          response_fn.(input)

        2 ->
          response_fn.(input, context)

        3 ->
          # New arity for functions that want conversation history
          response_fn.(input, context, conversation_history)

        arity ->
          raise ArgumentError, "response_fn has arity #{arity}, must be 1, 2, or 3"
      end
    rescue
      _e in FunctionClauseError ->
        reraise "FunctionClauseError calling response_fn with input #{inspect(input)}. Check that response function has correct arity and accepts the provided input.",
                __STACKTRACE__
    end
  end
end
