defmodule ExEval.Reporter.PubSub do
  @moduledoc """
  Phoenix.PubSub reporter for ExEval evaluation results.

  Broadcasts evaluation progress and results to Phoenix.PubSub topics for real-time
  updates in LiveView or other subscribers.

  ## Usage

  This reporter is only available when `phoenix_pubsub` is included in your dependencies.

      # In your mix.exs
      {:phoenix_pubsub, "~> 2.0"}

  Configure the reporter with your PubSub module and topic:

      ExEval.Runner.run(evaluations,
        reporter: ExEval.Reporter.PubSub,
        reporter_config: %{
          pubsub: MyApp.PubSub,
          topic: "evaluations:run:123"
        }
      )

  ## Broadcasted Events

  The reporter broadcasts the following events:

  - `{:evaluation_started, %{run_id, total_cases, started_at}}`
  - `{:evaluation_progress, %{run_id, result, completed, total, percent}}`
  - `{:evaluation_completed, %{run_id, passed, failed, errors, duration_ms}}`

  ## Configuration

  - `:pubsub` - The PubSub module to use (required)
  - `:topic` - The topic to broadcast to (defaults to "ex_eval:run:{run_id}")
  - `:broadcast_results` - Whether to include full results in progress events (default: true)
  """

  @behaviour ExEval.Reporter

  defstruct [
    :pubsub,
    :topic,
    :run_id,
    :total_cases,
    :completed,
    :broadcast_results,
    :failed_results,
    :error_results,
    :started_at
  ]

  @impl ExEval.Reporter
  def init(runner, config) do
    pubsub = config[:pubsub] || raise ArgumentError, "PubSub module is required"

    total_cases = count_total_cases(runner.datasets)
    topic = config[:topic] || "ex_eval:run:#{runner.id}"

    state = %__MODULE__{
      pubsub: pubsub,
      topic: topic,
      run_id: runner.id,
      total_cases: total_cases,
      completed: 0,
      broadcast_results: Map.get(config, :broadcast_results, true),
      failed_results: [],
      error_results: [],
      started_at: runner.started_at
    }

    # Broadcast start event
    Phoenix.PubSub.broadcast(
      pubsub,
      topic,
      {:evaluation_started,
       %{
         run_id: runner.id,
         total_cases: total_cases,
         started_at: runner.started_at,
         metadata: runner.metadata
       }}
    )

    {:ok, state}
  end

  @impl ExEval.Reporter
  def report_result(result, state, _config) do
    new_state = %{state | completed: state.completed + 1}

    # Track failed/error results
    new_state =
      case result.status do
        :failed -> %{new_state | failed_results: [result | new_state.failed_results]}
        :error -> %{new_state | error_results: [result | new_state.error_results]}
        _ -> new_state
      end

    percent = calculate_progress(new_state.completed, new_state.total_cases)

    # Prepare the progress event
    progress_data = %{
      run_id: state.run_id,
      completed: new_state.completed,
      total: new_state.total_cases,
      percent: percent,
      passed:
        new_state.completed - length(new_state.failed_results) - length(new_state.error_results),
      failed: length(new_state.failed_results),
      errors: length(new_state.error_results)
    }

    # Optionally include the full result
    progress_data =
      if state.broadcast_results do
        Map.put(progress_data, :result, result)
      else
        progress_data
      end

    # Broadcast progress event
    Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:evaluation_progress, progress_data})

    {:ok, new_state}
  end

  @impl ExEval.Reporter
  def finalize(runner, state, _config) do
    duration_ms =
      if runner.finished_at && runner.started_at do
        DateTime.diff(runner.finished_at, runner.started_at, :millisecond)
      else
        0
      end

    passed = state.completed - length(state.failed_results) - length(state.error_results)

    # Broadcast completion event
    Phoenix.PubSub.broadcast(
      state.pubsub,
      state.topic,
      {:evaluation_completed,
       %{
         run_id: state.run_id,
         total: state.completed,
         passed: passed,
         failed: length(state.failed_results),
         errors: length(state.error_results),
         duration_ms: duration_ms,
         finished_at: runner.finished_at,
         metadata: runner.metadata
       }}
    )

    :ok
  end

  defp count_total_cases(datasets) do
    Enum.reduce(datasets, 0, fn dataset, acc ->
      acc + length(Map.get(dataset, :cases, []))
    end)
  end

  defp calculate_progress(completed, total) when total > 0 do
    Float.round(completed / total * 100, 1)
  end

  defp calculate_progress(_, _), do: 0.0
end
