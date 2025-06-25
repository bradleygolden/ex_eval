defmodule ExEval.Reporter.TestMock do
  @moduledoc """
  Mock reporter that sends messages to the test process instead of printing to console.

  This reporter allows tests to capture evaluation events by receiving messages
  in the test process, enabling clean testing without console noise.
  """

  @behaviour ExEval.Reporter

  @impl ExEval.Reporter
  def init(runner, config) do
    test_pid = Keyword.get(config, :test_pid, self())

    send(
      test_pid,
      {:eval_started,
       %{
         total_count: length(runner.datasets),
         seed: :rand.uniform(999_999)
       }}
    )

    {:ok, %{test_pid: test_pid}}
  end

  @impl ExEval.Reporter
  def report_result(result, state, _config) do
    send(state.test_pid, {:eval_result, result})
    {:ok, state}
  end

  @impl ExEval.Reporter
  def finalize(runner, state, _config) do
    duration_ms = DateTime.diff(runner.finished_at, runner.started_at, :millisecond)

    total = length(runner.results)

    passed =
      Enum.count(runner.results, fn result ->
        Map.get(result, :judgment) == :pass or Map.get(result, :status) == :pass
      end)

    failed =
      Enum.count(runner.results, fn result ->
        Map.get(result, :judgment) == :fail or Map.get(result, :status) == :fail
      end)

    errors =
      Enum.count(runner.results, fn result ->
        Map.get(result, :judgment) == :error or Map.get(result, :status) == :error
      end)

    send(
      state.test_pid,
      {:eval_finished,
       %{
         total: total,
         passed: passed,
         failed: failed,
         errors: errors,
         duration_ms: duration_ms,
         results: runner.results
       }}
    )

    :ok
  end
end
