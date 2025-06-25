defmodule ExEval.Reporter.PubSubTest do
  use ExUnit.Case

  describe "PubSub Reporter" do
    setup do
      # Subscribe to test topic using the shared test PubSub
      Phoenix.PubSub.subscribe(TestPubSub, "test:evaluation")
      :ok
    end

    test "init/2 broadcasts evaluation_started event" do
      runner = %ExEval.Runner{
        id: "test-run-123",
        datasets: [
          %{cases: [%{input: "test1"}, %{input: "test2"}], response_fn: fn _ -> "ok" end},
          %{cases: [%{input: "test3"}], response_fn: fn _ -> "ok" end}
        ],
        options: [],
        metadata: %{test: true},
        started_at: DateTime.utc_now()
      }

      config = %{
        pubsub: TestPubSub,
        topic: "test:evaluation"
      }

      {:ok, state} = ExEval.Reporter.PubSub.init(runner, config)

      assert_receive {:evaluation_started, event_data}
      assert event_data.run_id == "test-run-123"
      assert event_data.total_cases == 3
      assert event_data.metadata == %{test: true}
      assert event_data.started_at == runner.started_at

      assert state.total_cases == 3
      assert state.completed == 0
      assert state.pubsub == TestPubSub
      assert state.topic == "test:evaluation"
    end

    test "init/2 uses default topic when not provided" do
      runner = %ExEval.Runner{
        id: "test-run-456",
        datasets: [],
        options: [],
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      # Subscribe to default topic pattern
      Phoenix.PubSub.subscribe(TestPubSub, "ex_eval:run:test-run-456")

      config = %{pubsub: TestPubSub}

      {:ok, state} = ExEval.Reporter.PubSub.init(runner, config)

      assert state.topic == "ex_eval:run:test-run-456"
      assert_receive {:evaluation_started, _}
    end

    test "init/2 raises when pubsub module not provided" do
      runner = %ExEval.Runner{
        id: "test-run",
        datasets: [],
        options: [],
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      assert_raise ArgumentError, "PubSub module is required", fn ->
        ExEval.Reporter.PubSub.init(runner, %{})
      end
    end

    test "report_result/3 broadcasts progress event with result" do
      state = %ExEval.Reporter.PubSub{
        pubsub: TestPubSub,
        topic: "test:evaluation",
        run_id: "test-run-789",
        total_cases: 10,
        completed: 2,
        broadcast_results: true,
        failed_results: [],
        error_results: [],
        started_at: DateTime.utc_now()
      }

      result = %{
        status: :passed,
        input: "test input",
        response: "test response",
        reasoning: "Good response",
        category: "test",
        duration_ms: 100
      }

      {:ok, new_state} = ExEval.Reporter.PubSub.report_result(result, state, %{})

      assert_receive {:evaluation_progress, event_data}
      assert event_data.run_id == "test-run-789"
      assert event_data.completed == 3
      assert event_data.total == 10
      assert event_data.percent == 30.0
      assert event_data.passed == 3
      assert event_data.failed == 0
      assert event_data.errors == 0
      assert event_data.result == result

      assert new_state.completed == 3
    end

    test "report_result/3 tracks failed and error results" do
      state = %ExEval.Reporter.PubSub{
        pubsub: TestPubSub,
        topic: "test:evaluation",
        run_id: "test-run",
        total_cases: 5,
        completed: 0,
        broadcast_results: false,
        failed_results: [],
        error_results: [],
        started_at: DateTime.utc_now()
      }

      # Report a passed result
      passed_result = %{status: :passed}
      {:ok, state} = ExEval.Reporter.PubSub.report_result(passed_result, state, %{})

      assert_receive {:evaluation_progress, event1}
      assert event1.passed == 1
      assert event1.failed == 0
      assert event1.errors == 0
      # broadcast_results is false
      refute Map.has_key?(event1, :result)

      # Report a failed result
      failed_result = %{status: :failed, reasoning: "Wrong answer"}
      {:ok, state} = ExEval.Reporter.PubSub.report_result(failed_result, state, %{})

      assert_receive {:evaluation_progress, event2}
      assert event2.passed == 1
      assert event2.failed == 1
      assert event2.errors == 0

      # Report an error result
      error_result = %{status: :error, error: "Timeout"}
      {:ok, state} = ExEval.Reporter.PubSub.report_result(error_result, state, %{})

      assert_receive {:evaluation_progress, event3}
      assert event3.passed == 1
      assert event3.failed == 1
      assert event3.errors == 1
      assert event3.percent == 60.0

      assert length(state.failed_results) == 1
      assert length(state.error_results) == 1
    end

    test "finalize/3 broadcasts evaluation_completed event" do
      state = %ExEval.Reporter.PubSub{
        pubsub: TestPubSub,
        topic: "test:evaluation",
        run_id: "test-run-final",
        total_cases: 10,
        completed: 10,
        broadcast_results: true,
        failed_results: [%{status: :failed}, %{status: :failed}],
        error_results: [%{status: :error}],
        started_at: DateTime.utc_now()
      }

      runner = %ExEval.Runner{
        id: "test-run-final",
        datasets: [],
        options: [],
        metadata: %{version: "1.0"},
        started_at: state.started_at,
        finished_at: DateTime.utc_now(),
        results: []
      }

      :ok = ExEval.Reporter.PubSub.finalize(runner, state, %{})

      assert_receive {:evaluation_completed, event_data}
      assert event_data.run_id == "test-run-final"
      assert event_data.total == 10
      # 10 - 2 failed - 1 error
      assert event_data.passed == 7
      assert event_data.failed == 2
      assert event_data.errors == 1
      assert event_data.duration_ms >= 0
      assert event_data.finished_at == runner.finished_at
      assert event_data.metadata == %{version: "1.0"}
    end

    test "progress calculation handles edge cases" do
      state = %ExEval.Reporter.PubSub{
        pubsub: TestPubSub,
        topic: "test:evaluation",
        run_id: "test",
        # Edge case: no cases
        total_cases: 0,
        completed: 0,
        broadcast_results: true,
        failed_results: [],
        error_results: [],
        started_at: DateTime.utc_now()
      }

      result = %{status: :passed}
      {:ok, _} = ExEval.Reporter.PubSub.report_result(result, state, %{})

      assert_receive {:evaluation_progress, event_data}
      # Should handle division by zero
      assert event_data.percent == 0.0
    end
  end
end
