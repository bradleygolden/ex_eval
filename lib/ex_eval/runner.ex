defmodule ExEval.Runner do
  @moduledoc """
  Async-first runner for ExEval evaluation suites.

  This runner manages evaluation runs as supervised processes, providing:
  - Async execution with real-time status updates
  - Process supervision and fault tolerance
  - LiveView-friendly API
  - Support for both module and data-based datasets
  """

  use GenServer
  require Logger

  @default_timeout 120_000
  @default_max_concurrency 5

  defstruct [
    :id,
    :datasets,
    :options,
    :metadata,
    :reporter_module,
    :reporter_config,
    :reporter_state,
    :supervisor,
    status: :pending,
    results: [],
    started_at: nil,
    finished_at: nil,
    error: nil
  ]

  ## Client API

  @doc """
  Starts a supervised runner process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Runs evaluations asynchronously.
  Returns `{:ok, run_id}` immediately.

  ## Options
  - `:parallel` - Run evaluations in parallel (default: true)
  - `:max_concurrency` - Maximum concurrent evaluations (default: #{@default_max_concurrency})
  - `:timeout` - Timeout per evaluation in ms (default: #{@default_timeout})
  - `:categories` - Filter by specific categories
  - `:reporter` - Reporter module (default: ExEval.Reporter.Console)
  - `:reporter_config` - Configuration for the reporter
  - `:metadata` - Custom metadata to attach to the run
  """
  def run(datasets, options \\ []) do
    run_id = generate_run_id()
    supervisor = options[:supervisor] || ExEval.RunnerSupervisor

    # Start a dedicated process for this run
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        supervisor,
        {__MODULE__, Keyword.merge(options, run_id: run_id, datasets: datasets)}
      )

    {:ok, run_id}
  end

  @doc """
  Runs evaluations synchronously (blocking).
  Useful for tests and CLI usage.
  """
  def run_sync(datasets, options \\ []) do
    # Add the caller's PID to options so the runner can send results back
    caller = self()
    options_with_sync = Keyword.merge(options, sync_caller: caller)

    {:ok, run_id} = run(datasets, options_with_sync)

    # Wait for the final state from the runner
    receive do
      {:runner_complete, ^run_id, final_state} ->
        final_state
    after
      options[:timeout] || 120_000 ->
        # Timeout - try to get current state
        case get_run(run_id, options) do
          {:ok, state} ->
            state

          {:error, _} ->
            %{
              id: run_id,
              status: :error,
              results: [],
              error: "Evaluation timed out",
              started_at: DateTime.utc_now(),
              finished_at: DateTime.utc_now(),
              metadata: options[:metadata] || %{},
              options: options
            }
        end
    end
  end

  @doc """
  Gets the current state of a run.
  """
  def get_run(run_id, options \\ []) do
    registry = options[:registry] || ExEval.RunnerRegistry

    case Registry.lookup(registry, run_id) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :get_state)
        catch
          :exit, {:normal, _} ->
            {:error, :not_found}

          :exit, {:noproc, _} ->
            {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active runs.
  """
  def list_active_runs(options \\ []) do
    registry = options[:registry] || ExEval.RunnerRegistry

    registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.map(fn {run_id, pid, _} ->
      try do
        case GenServer.call(pid, :get_state, 5000) do
          {:ok, state} -> {run_id, state}
          _ -> nil
        end
      catch
        :exit, _ ->
          # Process has already exited
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Cancels a running evaluation.
  """
  def cancel_run(run_id, options \\ []) do
    registry = options[:registry] || ExEval.RunnerRegistry

    case Registry.lookup(registry, run_id) do
      [{pid, _}] ->
        GenServer.call(pid, :cancel)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Subscribes to updates for a specific run.
  Useful for LiveView integration.
  """
  def subscribe(run_id, options \\ []) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      pubsub = options[:pubsub] || ExEval.PubSub
      Phoenix.PubSub.subscribe(pubsub, "runner:#{run_id}")
    else
      {:error, :pubsub_not_available}
    end
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    run_id = opts[:run_id] || generate_run_id()
    datasets = opts[:datasets] || []
    registry = opts[:registry] || ExEval.RunnerRegistry

    Registry.register(registry, run_id, self())

    state = %__MODULE__{
      id: run_id,
      datasets: datasets,
      options: Keyword.merge(default_options(), opts),
      metadata: Keyword.get(opts, :metadata, %{}),
      reporter_module: opts[:reporter] || ExEval.Reporter.Console,
      reporter_config: opts[:reporter_config] || %{}
    }

    send(self(), :start_evaluation)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_evaluation, state) do
    state = %{state | status: :running, started_at: DateTime.utc_now()}

    # Initialize reporter
    case state.reporter_module.init(state, state.reporter_config) do
      {:ok, reporter_state} ->
        state = %{state | reporter_state: reporter_state}

        # Start running evaluations
        send(self(), :run_evaluations)
        {:noreply, state}

      {:error, reason} ->
        state = %{state | status: :error, error: reason, finished_at: DateTime.utc_now()}
        broadcast_update(state)

        # If this is a sync run, send the final state to the caller
        if sync_caller = state.options[:sync_caller] do
          send(sync_caller, {:runner_complete, state.id, public_state(state)})
        end

        {:stop, :normal, state}
    end
  end

  def handle_info(:run_evaluations, state) do
    {results, final_reporter_state} =
      if state.options[:parallel] do
        run_parallel(state)
      else
        run_sequential(state)
      end

    # Finalize
    state = %{
      state
      | results: results,
        reporter_state: final_reporter_state,
        status: :completed,
        finished_at: DateTime.utc_now()
    }

    # Finalize reporter
    state.reporter_module.finalize(state, final_reporter_state, state.reporter_config)

    # Broadcast completion
    broadcast_update(state)

    # If this is a sync run, send the final state to the caller
    if sync_caller = state.options[:sync_caller] do
      send(sync_caller, {:runner_complete, state.id, public_state(state)})
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, public_state(state)}, state}
  end

  def handle_call(:cancel, _from, state) do
    # TODO: Implement cancellation logic for running tasks
    state = %{state | status: :cancelled, finished_at: DateTime.utc_now()}
    broadcast_update(state)
    {:stop, :normal, {:ok, :cancelled}, state}
  end

  ## Private Functions

  defp default_options do
    [
      parallel: true,
      max_concurrency: @default_max_concurrency,
      timeout: @default_timeout
    ]
  end

  defp run_parallel(state) do
    all_cases = prepare_all_cases(state)

    {results, final_reporter_state} =
      all_cases
      |> run_cases_async(state)
      |> process_async_results(state)

    {Enum.reverse(results), final_reporter_state}
  end

  defp run_sequential(state) do
    {results, final_reporter_state} =
      state.datasets
      |> Enum.reduce({[], state.reporter_state}, fn dataset, {results_acc, reporter_state_acc} ->
        dataset_results = run_dataset_sequential(dataset, state, reporter_state_acc)
        {results_acc ++ dataset_results.results, dataset_results.reporter_state}
      end)

    {results, final_reporter_state}
  end

  defp prepare_all_cases(state) do
    state.datasets
    |> Enum.flat_map(fn dataset ->
      context =
        case ExEval.Dataset.setup_fn(dataset) do
          nil -> %{}
          setup_fn -> setup_fn.()
        end

      dataset
      |> ExEval.Dataset.cases()
      |> filter_by_categories(state.options[:categories])
      |> Enum.map(fn eval_case ->
        {dataset, eval_case, ExEval.Dataset.response_fn(dataset), context}
      end)
    end)
  end

  defp run_cases_async(cases, state) do
    Task.async_stream(
      cases,
      fn {dataset, eval_case, response_fn, context} ->
        run_eval_case(eval_case, response_fn, dataset, context, state)
      end,
      max_concurrency: state.options[:max_concurrency],
      timeout: state.options[:timeout],
      on_timeout: :kill_task
    )
  end

  defp process_async_results(stream, state) do
    Enum.reduce(stream, {[], state.reporter_state}, fn stream_result,
                                                       {results_acc, reporter_state_acc} ->
      result = handle_stream_result(stream_result, state)

      # Report result
      {:ok, new_reporter_state} =
        state.reporter_module.report_result(result, reporter_state_acc, state.reporter_config)

      # Broadcast progress
      broadcast_progress(state, length(results_acc) + 1)

      {[result | results_acc], new_reporter_state}
    end)
  end

  defp run_dataset_sequential(dataset, state, reporter_state) do
    context =
      case ExEval.Dataset.setup_fn(dataset) do
        nil -> %{}
        setup_fn -> setup_fn.()
      end

    response_fn = ExEval.Dataset.response_fn(dataset)

    {results, final_reporter_state} =
      dataset
      |> ExEval.Dataset.cases()
      |> filter_by_categories(state.options[:categories])
      |> Enum.reduce({[], reporter_state}, fn eval_case, {case_results, reporter_state_acc} ->
        result = run_eval_case(eval_case, response_fn, dataset, context, state)

        {:ok, new_reporter_state} =
          state.reporter_module.report_result(result, reporter_state_acc, state.reporter_config)

        broadcast_progress(state, length(state.results) + length(case_results) + 1)

        {[result | case_results], new_reporter_state}
      end)

    %{results: Enum.reverse(results), reporter_state: final_reporter_state}
  end

  defp filter_by_categories(eval_cases, nil), do: eval_cases
  defp filter_by_categories(eval_cases, []), do: eval_cases

  defp filter_by_categories(eval_cases, categories) do
    Enum.filter(eval_cases, fn case_data ->
      Map.get(case_data, :category) in categories
    end)
  end

  defp run_eval_case(eval_case, response_fn, dataset, context, _state) do
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
      dataset: ExEval.Dataset.metadata(dataset),
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

  defp apply_response_fn(response_fn, input, context, conversation_history) do
    arity = :erlang.fun_info(response_fn)[:arity]

    try do
      case arity do
        1 ->
          response_fn.(input)

        2 ->
          response_fn.(input, context)

        3 ->
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

  defp run_judge(dataset, response, judge_prompt) do
    judge_config = ExEval.Dataset.judge_config(dataset)

    ExEval.Judge.evaluate(
      ExEval.new(
        judge_provider: judge_config.provider,
        config: judge_config.config
      ),
      response,
      judge_prompt
    )
  end

  defp format_judge_result(judge_result, response) do
    case judge_result do
      {:ok, true, reasoning} ->
        %{status: :passed, reasoning: reasoning}

      {:ok, false, reasoning} ->
        %{status: :failed, reasoning: reasoning, response: response}

      {:error, error} ->
        %{status: :error, error: "Judge error: #{inspect(error)}"}
    end
  end

  defp handle_stream_result(stream_result, state) do
    case stream_result do
      {:ok, result} ->
        result

      {:exit, :timeout} ->
        %{
          status: :error,
          error: "Evaluation timed out after #{state.options[:timeout]}ms"
        }

      {:exit, reason} ->
        %{
          status: :error,
          error: "Evaluation crashed: #{inspect(reason)}"
        }
    end
  end

  defp get_module_from_dataset(dataset) do
    case ExEval.Dataset.metadata(dataset) do
      %{module: module} -> module
      _ -> nil
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp broadcast_update(state) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      pubsub = state.options[:pubsub] || ExEval.PubSub

      Phoenix.PubSub.broadcast(
        pubsub,
        "runner:#{state.id}",
        {:runner_update, state.id, public_state(state)}
      )
    end
  end

  defp broadcast_progress(state, completed_count) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      pubsub = state.options[:pubsub] || ExEval.PubSub

      total_count =
        state.datasets
        |> Enum.map(&length(ExEval.Dataset.cases(&1)))
        |> Enum.sum()

      Phoenix.PubSub.broadcast(
        pubsub,
        "runner:#{state.id}",
        {:runner_progress, state.id,
         %{
           completed: completed_count,
           total: total_count,
           percent: Float.round(completed_count / total_count * 100, 1)
         }}
      )
    end
  end

  defp public_state(state) do
    %{
      id: state.id,
      status: state.status,
      started_at: state.started_at,
      finished_at: state.finished_at,
      metadata: state.metadata,
      results: state.results,
      error: state.error,
      options: state.options
    }
  end
end
