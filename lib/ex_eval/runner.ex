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
  def run(%ExEval{} = config, opts \\ []) do
    datasets = convert_inline_config_to_dataset(config)
    run_id = generate_run_id()

    options =
      [
        run_id: run_id,
        datasets: datasets,
        eval_config: config,
        supervisor: Keyword.get(opts, :supervisor, ExEval.RunnerSupervisor)
      ] ++ opts

    # Start a dedicated process for this run
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        options[:supervisor],
        {__MODULE__, options}
      )

    {:ok, run_id}
  end

  @doc """
  Runs evaluations synchronously (blocking).
  Useful for tests and CLI usage.
  """
  def run_sync(%ExEval{} = config, opts \\ []) do
    datasets = convert_inline_config_to_dataset(config)
    # Add the caller's PID to options so the runner can send results back
    caller = self()

    # Include extra options like categories, registry, etc.
    options =
      [
        run_id: generate_run_id(),
        datasets: datasets,
        eval_config: config,
        sync_caller: caller,
        supervisor: Keyword.get(opts, :supervisor, ExEval.RunnerSupervisor)
      ] ++ opts

    # Start a dedicated process for this run
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        options[:supervisor],
        {__MODULE__, options}
      )

    run_id = options[:run_id]

    # Wait for the final state from the runner
    receive do
      {:runner_complete, ^run_id, final_state} ->
        final_state
    after
      config.timeout || 120_000 ->
        # Timeout - try to get current state
        case get_run(run_id, opts) do
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
              metadata: %{},
              options: []
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
        if Process.alive?(pid) do
          try do
            GenServer.call(pid, :cancel, 1000)
          catch
            :exit, :normal ->
              {:ok, :cancelled}

            :exit, {:normal, _} ->
              {:ok, :cancelled}

            :exit, {:noproc, _} ->
              {:ok, :cancelled}
          end
        else
          # Process is already dead, consider it cancelled
          {:ok, :cancelled}
        end

      [] ->
        {:error, :not_found}
    end
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    run_id = opts[:run_id] || generate_run_id()
    datasets = opts[:datasets] || []
    registry = opts[:registry] || ExEval.RunnerRegistry
    eval_config = opts[:eval_config]
    
    unless eval_config do
      {:stop, {:error, "ExEval config required"}}
    else

    Registry.register(registry, run_id, self())

    # Extract options from ExEval struct
    options = [
      parallel: eval_config.parallel,
      max_concurrency: eval_config.max_concurrency,
      timeout: eval_config.timeout,
      eval_config: eval_config
    ]

    # Add any additional options passed in
    options = Keyword.merge(options, Keyword.drop(opts, [:run_id, :datasets, :eval_config]))

    {reporter_module, reporter_config} =
      case eval_config.reporter do
        {module, opts} when is_atom(module) and is_list(opts) ->
          {module, Enum.into(opts, %{})}

        module when is_atom(module) ->
          {module, %{}}

        _ ->
          {ExEval.Reporter.Console, %{}}
      end

    options =
      if eval_config.store do
        Keyword.put(options, :store_module, eval_config.store)
      else
        options
      end

    state = %__MODULE__{
      id: run_id,
      datasets: datasets,
      options: options,
      metadata: build_run_metadata(eval_config, opts),
      reporter_module: reporter_module,
      reporter_config: reporter_config
    }

    send(self(), :start_evaluation)

    {:ok, state}
    end
  end

  @impl true
  def handle_info(:start_evaluation, state) do
    state = %{state | status: :running, started_at: DateTime.utc_now()}

    case state.reporter_module.init(state, state.reporter_config) do
      {:ok, reporter_state} ->
        state = %{state | reporter_state: reporter_state}

        # Start running evaluations
        send(self(), :run_evaluations)
        {:noreply, state}

      {:error, reason} ->
        state = %{state | status: :error, error: reason, finished_at: DateTime.utc_now()}

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

    # Save run to store if experiment is configured
    final_public_state = public_state(state)

    if get_in(state.metadata, [:experiment]) && state.options[:store_module] do
      save_to_store(state.options[:store_module], final_public_state)
    end

    # If this is a sync run, send the final state to the caller
    if sync_caller = state.options[:sync_caller] do
      send(sync_caller, {:runner_complete, state.id, final_public_state})
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, public_state(state)}, state}
  end

  def handle_call(:cancel, _from, state) do
    # Finalize reporter if it was initialized
    if state.reporter_state do
      state.reporter_module.finalize(state, state.reporter_state, state.reporter_config)
    end

    state = %{state | status: :cancelled, finished_at: DateTime.utc_now()}

    # If this is a sync run, send the final state to the caller
    if sync_caller = state.options[:sync_caller] do
      send(sync_caller, {:runner_complete, state.id, public_state(state)})
    end

    # Stop the process, which will cancel any ongoing async operations
    {:stop, :normal, {:ok, :cancelled}, state}
  end

  ## Private Functions

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

  defp run_eval_case(eval_case, response_fn, dataset, context, state) do
    start_time = System.monotonic_time(:millisecond)
    eval_config = state.options[:eval_config]

    evaluation_context = %{
      input: eval_case.input,
      criteria: eval_case.judge_prompt,
      dataset: dataset,
      context: context
    }

    result =
      try do
        # Wrap the core evaluation with middleware
        core_evaluation = fn ->
          run_core_evaluation(eval_case, response_fn, dataset, context, state)
        end

        ExEval.Pipeline.with_middleware(
          core_evaluation,
          eval_config.middleware,
          evaluation_context
        )
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

  defp run_core_evaluation(eval_case, response_fn, dataset, context, state) do
    eval_config = state.options[:eval_config]

    # Step 1: Apply preprocessors to input
    with {:ok, processed_input} <-
           apply_pipeline_step(eval_case.input, eval_config.preprocessors, :preprocessors),
         # Step 2: Generate response with processed input
         processed_case = %{eval_case | input: processed_input},
         {response, judge_prompt} = get_response_and_prompt(processed_case, response_fn, context),
         # Step 3: Apply response processors
         {:ok, processed_response} <-
           apply_pipeline_step(response, eval_config.response_processors, :response_processors),
         # Step 4: Run judge with processed response
         judge_result = run_judge(dataset, processed_response, judge_prompt, state),
         # Step 5: Apply postprocessors to judge result
         {:ok, final_result} <-
           apply_pipeline_step(judge_result, eval_config.postprocessors, :postprocessors) do
      # Step 6: Format the final result
      format_judge_result(final_result, processed_response)
    else
      {:error, stage, reason} ->
        %{status: :error, error: "#{stage} failed: #{reason}"}
    end
  end

  defp apply_pipeline_step(data, [], _stage), do: {:ok, data}

  defp apply_pipeline_step(data, processors, stage) do
    case stage do
      :preprocessors ->
        case ExEval.Pipeline.run_preprocessors(data, processors) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, :preprocessor, reason}
          result -> {:ok, result}
        end

      :response_processors ->
        case ExEval.Pipeline.run_response_processors(data, processors) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, :response_processor, reason}
          result -> {:ok, result}
        end

      :postprocessors ->
        case ExEval.Pipeline.run_postprocessors(data, processors) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, :postprocessor, reason}
          result -> {:ok, result}
        end
    end
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

  defp run_judge(dataset, response, judge_prompt, state) do
    dataset_judge_config = ExEval.Dataset.judge_config(dataset)
    eval_config = state.options[:eval_config]

    # Determine which judge configuration to use
    judge =
      cond do
        # Dataset has a specific judge
        dataset_judge_config.judge ->
          # Convert dataset config to tuple format
          config_list = Map.to_list(dataset_judge_config.config)

          if config_list == [] do
            dataset_judge_config.judge
          else
            {dataset_judge_config.judge, config_list}
          end

        # Use ExEval's judge configuration
        eval_config.judge ->
          eval_config.judge

        # No judge configured
        true ->
          raise ArgumentError, """
          No judge configured.

          Configure one when creating the ExEval config:

              ExEval.new()
              |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
          """
      end

    ExEval.Evaluator.evaluate(judge, response, judge_prompt)
  end

  defp format_judge_result(judge_result, response) do
    case judge_result do
      {:ok, result, metadata} when is_map(metadata) ->
        base_result = %{
          result: result,
          metadata: metadata,
          response: response
        }

        # Extract reasoning from metadata if present
        base_with_reasoning =
          if reasoning = metadata[:reasoning] do
            Map.put(base_result, :reasoning, reasoning)
          else
            base_result
          end

        # Set status based on result type
        final_status =
          case result do
            true -> :passed
            false -> :failed
            _ -> :evaluated
          end

        Map.put(base_with_reasoning, :status, final_status)

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

  # Convert inline ExEval config to a dataset that can be processed
  defp convert_inline_config_to_dataset(%ExEval{dataset: dataset, response_fn: response_fn})
       when not is_nil(dataset) and not is_nil(response_fn) do
    # Create a map that implements the Dataset protocol
    [
      %{
        cases: dataset,
        response_fn: response_fn,
        metadata: %{type: :inline, source: :config}
      }
    ]
  end

  defp convert_inline_config_to_dataset(%ExEval{}) do
    []
  end

  defp public_state(state) do
    base_state = %{
      id: state.id,
      status: state.status,
      started_at: state.started_at,
      finished_at: state.finished_at,
      metadata: state.metadata,
      results: state.results,
      error: state.error,
      options: state.options
    }

    # Add metrics if run is completed
    if state.status == :completed and state.results != [] do
      Map.put(base_state, :metrics, ExEval.Metrics.compute(state.results))
    else
      base_state
    end
  end

  defp build_run_metadata(eval_config, opts) do
    base_metadata = Keyword.get(opts, :metadata, %{})

    Map.merge(base_metadata, %{
      experiment: eval_config.experiment,
      params: eval_config.params,
      tags: eval_config.tags,
      artifact_logging: eval_config.artifact_logging
    })
  end

  defp save_to_store(store_config, run_data) do
    case store_config do
      {module, _opts} when is_atom(module) ->
        if function_exported?(module, :save_run, 1) do
          # Store implementations handle their own configuration
          case module.save_run(run_data) do
            :ok -> :ok
            {:ok, _} = result -> result
            {:error, _} = error -> 
              Logger.error("Store save failed: #{inspect(error)}")
              error
            other ->
              Logger.error("Store save returned unexpected value: #{inspect(other)}")
              {:error, :invalid_store_response}
          end
        else
          Logger.error("Store module #{inspect(module)} does not implement save_run/1")
          {:error, :invalid_store_module}
        end

      module when is_atom(module) ->
        if function_exported?(module, :save_run, 1) do
          case module.save_run(run_data) do
            :ok -> :ok
            {:ok, _} = result -> result
            {:error, _} = error ->
              Logger.error("Store save failed: #{inspect(error)}")
              error
            other ->
              Logger.error("Store save returned unexpected value: #{inspect(other)}")
              {:error, :invalid_store_response}
          end
        else
          Logger.error("Store module #{inspect(module)} does not implement save_run/1")
          {:error, :invalid_store_module}
        end
          
      _ ->
        Logger.error("Invalid store configuration: #{inspect(store_config)}")
        {:error, :invalid_store_config}
    end
  end
end
