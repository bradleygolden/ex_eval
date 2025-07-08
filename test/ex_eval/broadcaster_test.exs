defmodule ExEval.BroadcasterTest do
  use ExUnit.Case, async: false
  alias ExEval.SilentReporter
  import ExUnit.CaptureLog

  # Helper function to run evaluation with captured logs
  defp run_with_captured_logs(config, opts) do
    # Use Agent to store the result while capturing logs
    {:ok, agent} = Agent.start_link(fn -> nil end)

    # Capture all log levels including warnings and notices
    _log_output =
      capture_log([level: :all], fn ->
        result = ExEval.run(config, opts)
        Agent.update(agent, fn _state -> result end)
      end)

    result = Agent.get(agent, & &1)
    Agent.stop(agent)
    result
  end

  # Helper function to run evaluation with captured logs and wait for completion
  defp run_with_captured_logs_and_wait(config, opts, broadcaster_name) do
    # Use Agent to store the result while capturing logs
    {:ok, agent} = Agent.start_link(fn -> nil end)

    # Capture all log levels including warnings and notices
    _log_output =
      capture_log([level: :all], fn ->
        result = ExEval.run(config, opts)
        Agent.update(agent, fn _state -> result end)

        # Wait for completion event to ensure all broadcaster operations are done
        receive do
          {:broadcast_event, ^broadcaster_name, :completed, _data, _prefix} -> :ok
        after
          1000 -> :timeout
        end

        # Wait briefly for async Task.start broadcaster operations to complete
        # The runner uses Task.start for fire-and-forget broadcaster calls,
        # so we need a short delay to capture their error logs
        :timer.sleep(50)
      end)

    result = Agent.get(agent, & &1)
    Agent.stop(agent)
    result
  end

  setup do
    # Ensure clean application state before each test
    Application.stop(:ex_eval)
    Application.ensure_all_started(:ex_eval)

    # Give the application a moment to fully start
    Process.sleep(10)

    # Verify supervision tree is running
    assert Process.whereis(ExEval.RunnerRegistry) != nil, "ExEval.RunnerRegistry not started"
    assert Process.whereis(ExEval.RunnerSupervisor) != nil, "ExEval.RunnerSupervisor not started"

    :ok
  end

  # Test broadcaster that sends messages to test process
  defmodule TestBroadcaster do
    @behaviour ExEval.Broadcaster

    @impl true
    def init(config) do
      {:ok,
       %{
         test_pid: config[:test_pid],
         prefix: config[:prefix] || "",
         name: config[:name] || "default"
       }}
    end

    @impl true
    def broadcast(event, data, state) do
      if state.test_pid do
        send(state.test_pid, {:broadcast_event, state.name, event, data, state.prefix})
      end

      :ok
    end

    @impl true
    def terminate(_reason, _state) do
      :ok
    end
  end

  # Failing broadcaster for error testing
  defmodule FailingBroadcaster do
    @behaviour ExEval.Broadcaster

    @impl true
    def init(_config) do
      {:error, "Intentional failure"}
    end

    @impl true
    def broadcast(_event, _data, _state) do
      raise "This should not be called"
    end
  end

  # Crashing broadcaster for error testing
  defmodule CrashingBroadcaster do
    @behaviour ExEval.Broadcaster

    @impl true
    def init(_config) do
      {:ok, %{}}
    end

    @impl true
    def broadcast(_event, _data, _state) do
      raise "Intentional crash"
    end
  end

  # Synchronous crashing broadcaster that sends completion signal
  defmodule SyncCrashingBroadcaster do
    @behaviour ExEval.Broadcaster

    @impl true
    def init(config) do
      {:ok, %{test_pid: config[:test_pid], name: config[:name]}}
    end

    @impl true
    def broadcast(event, data, state) do
      # Send the event to test process first
      if state.test_pid do
        send(state.test_pid, {:broadcast_event, state.name, event, data, ""})
      end

      # Then crash
      raise "Intentional crash"
    end
  end

  # Mock judge for testing
  defmodule MockJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:ok, true, %{reasoning: "Mock judge always returns true"}}
    end
  end

  # Helper function to collect broadcast events from messages
  defp collect_broadcast_events(expected_name, acc, timeout \\ 100) do
    receive do
      {:broadcast_event, ^expected_name, event, data, prefix} ->
        event_record = %{
          event: event,
          data: data,
          prefix: prefix,
          timestamp: DateTime.utc_now()
        }

        collect_broadcast_events(expected_name, [event_record | acc], 10)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end

  describe "single broadcaster" do
    setup do
      test_pid = self()
      broadcaster_name = "test_broadcaster_#{:rand.uniform(10000)}"

      config =
        ExEval.new()
        |> ExEval.put_broadcaster(TestBroadcaster, test_pid: test_pid, name: broadcaster_name)
        |> ExEval.put_dataset([
          %{input: "test1", judge_prompt: "always true"},
          %{input: "test2", judge_prompt: "always true"}
        ])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      %{config: config, broadcaster_name: broadcaster_name}
    end

    test "broadcasts evaluation lifecycle events", %{config: config, broadcaster_name: name} do
      # Run evaluation synchronously and capture all log output
      _results = run_with_captured_logs(config, async: false)

      # Collect all broadcast events
      events = collect_broadcast_events(name, [])

      # Should have at least started, progress, and completed events
      assert length(events) >= 3

      # Check started event
      started_event = Enum.find(events, &(&1.event == :started))
      assert started_event != nil
      assert started_event.data.total_cases == 2
      assert is_binary(started_event.data.run_id)

      # Check progress events
      progress_events = Enum.filter(events, &(&1.event == :progress))
      assert length(progress_events) >= 1

      # Check completed event
      completed_event = Enum.find(events, &(&1.event == :completed))
      assert completed_event != nil
      assert completed_event.data.status == :completed
      assert is_map(completed_event.data.metrics)
    end

    test "includes common fields in all events", %{config: config, broadcaster_name: name} do
      _results = run_with_captured_logs(config, async: false)

      events = collect_broadcast_events(name, [])

      # All events should have common fields
      for event <- events do
        assert is_binary(event.data.run_id)
        assert %DateTime{} = event.data.timestamp
      end
    end

    test "handles broadcaster initialization failure gracefully" do
      capture_log([level: :all], fn ->
        config =
          ExEval.new()
          |> ExEval.put_broadcaster(FailingBroadcaster)
          |> ExEval.put_dataset([%{input: "test", judge_prompt: "test"}])
          |> ExEval.put_response_fn(fn _input -> "response" end)
          |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
          |> ExEval.put_reporter(SilentReporter)

        # Should complete successfully even with broadcaster failure
        results = run_with_captured_logs(config, async: false)
        assert results.status == :completed
      end)
    end

    test "isolates broadcaster errors from evaluation" do
      test_pid = self()
      completion_name = "completion_#{:rand.uniform(10000)}"

      config =
        ExEval.new()
        |> ExEval.put_broadcasters([
          {CrashingBroadcaster, []},
          {TestBroadcaster, test_pid: test_pid, name: completion_name}
        ])
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "test"}])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      # Should complete successfully even with broadcaster crashes
      results = run_with_captured_logs_and_wait(config, [async: false], completion_name)
      assert results.status == :completed
    end
  end

  describe "multiple broadcasters" do
    setup do
      test_pid = self()
      broadcaster1_name = "test_broadcaster1_#{:rand.uniform(10000)}"
      broadcaster2_name = "test_broadcaster2_#{:rand.uniform(10000)}"

      config =
        ExEval.new()
        |> ExEval.put_broadcasters([
          {TestBroadcaster, test_pid: test_pid, name: broadcaster1_name, prefix: "B1"},
          {TestBroadcaster, test_pid: test_pid, name: broadcaster2_name, prefix: "B2"}
        ])
        |> ExEval.put_dataset([
          %{input: "test1", judge_prompt: "always true"},
          %{input: "test2", judge_prompt: "always true"}
        ])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      %{
        config: config,
        broadcaster1_name: broadcaster1_name,
        broadcaster2_name: broadcaster2_name
      }
    end

    test "broadcasts to all configured broadcasters", %{
      config: config,
      broadcaster1_name: name1,
      broadcaster2_name: name2
    } do
      _results = run_with_captured_logs(config, async: false)

      events1 = collect_broadcast_events(name1, [])
      events2 = collect_broadcast_events(name2, [])

      # Both broadcasters should receive events
      assert length(events1) >= 3
      assert length(events2) >= 3

      # Check that both received started events
      assert Enum.any?(events1, &(&1.event == :started))
      assert Enum.any?(events2, &(&1.event == :started))

      # Check prefixes are different
      assert Enum.all?(events1, &(&1.prefix == "B1"))
      assert Enum.all?(events2, &(&1.prefix == "B2"))
    end

    test "handles partial broadcaster failures in multi-broadcaster setup" do
      capture_log([level: :all], fn ->
        test_pid = self()
        working_name = "working_#{:rand.uniform(10000)}"

        config =
          ExEval.new()
          |> ExEval.put_broadcasters([
            {TestBroadcaster, test_pid: test_pid, name: working_name},
            # This will fail to initialize
            {FailingBroadcaster, []},
            # This will crash on broadcast
            {CrashingBroadcaster, []}
          ])
          |> ExEval.put_dataset([%{input: "test", judge_prompt: "test"}])
          |> ExEval.put_response_fn(fn _input -> "response" end)
          |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
          |> ExEval.put_reporter(SilentReporter)

        # Should complete successfully even with some broadcaster failures
        results = run_with_captured_logs_and_wait(config, [async: false], working_name)
        assert results.status == :completed

        # Now collect all events
        events = collect_broadcast_events(working_name, [])
        assert length(events) >= 1
      end)
    end

    test "handles empty broadcaster list" do
      config =
        ExEval.new()
        |> ExEval.put_broadcasters([])
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "test"}])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      # Should complete successfully with empty broadcaster list
      results = run_with_captured_logs(config, async: false)
      assert results.status == :completed
    end
  end

  describe "broadcaster configuration" do
    test "put_broadcaster/2 configures single broadcaster" do
      config =
        ExEval.new()
        |> ExEval.put_broadcaster(TestBroadcaster, name: :test)

      assert config.broadcaster == TestBroadcaster
      assert config.broadcaster_config == %{name: :test}
    end

    test "put_broadcaster/1 can disable broadcasting" do
      config =
        ExEval.new()
        |> ExEval.put_broadcaster(TestBroadcaster, name: :test)
        |> ExEval.put_broadcaster(nil)

      assert config.broadcaster == nil
      assert config.broadcaster_config == %{}
    end

    test "put_broadcasters/1 configures multiple broadcasters" do
      config =
        ExEval.new()
        |> ExEval.put_broadcasters([
          {TestBroadcaster, name: :test1},
          {TestBroadcaster, name: :test2}
        ])

      assert config.broadcaster == :multi

      assert config.broadcaster_config == %{
               broadcasters: [
                 {TestBroadcaster, name: :test1},
                 {TestBroadcaster, name: :test2}
               ]
             }
    end
  end

  describe "event data structure" do
    setup do
      test_pid = self()
      broadcaster_name = "event_test_#{:rand.uniform(10000)}"

      config =
        ExEval.new()
        |> ExEval.put_broadcaster(TestBroadcaster, test_pid: test_pid, name: broadcaster_name)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "test", category: :math}
        ])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      %{config: config, broadcaster_name: broadcaster_name}
    end

    test "started event contains expected data", %{config: config, broadcaster_name: name} do
      _results = run_with_captured_logs(config, async: false)

      events = collect_broadcast_events(name, [])
      started_event = Enum.find(events, &(&1.event == :started))

      assert started_event.data.total_cases == 1
      assert is_binary(started_event.data.run_id)
      assert %DateTime{} = started_event.data.started_at
      assert %DateTime{} = started_event.data.timestamp
    end

    test "progress event contains expected data", %{config: config, broadcaster_name: name} do
      _results = run_with_captured_logs(config, async: false)

      events = collect_broadcast_events(name, [])
      progress_event = Enum.find(events, &(&1.event == :progress))

      assert progress_event.data.completed >= 1
      assert progress_event.data.total == 1
      assert progress_event.data.percentage == 100.0
      assert is_map(progress_event.data.current_result)
    end

    test "completed event contains expected data", %{config: config, broadcaster_name: name} do
      _results = run_with_captured_logs(config, async: false)

      events = collect_broadcast_events(name, [])
      completed_event = Enum.find(events, &(&1.event == :completed))

      assert completed_event != nil,
             "No completed event found in #{inspect(Enum.map(events, & &1.event))}"

      assert completed_event.data.status == :completed
      assert is_map(completed_event.data.metrics)
      assert is_map(completed_event.data.results_summary)
      assert %DateTime{} = completed_event.data.finished_at
      assert is_integer(completed_event.data.duration_ms)
    end
  end

  describe "async run integration" do
    test "broadcasts events for async runs" do
      test_pid = self()
      broadcaster_name = "async_test_#{:rand.uniform(10000)}"

      config =
        ExEval.new()
        |> ExEval.put_broadcaster(TestBroadcaster, test_pid: test_pid, name: broadcaster_name)
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "test"}])
        |> ExEval.put_response_fn(fn _input -> "response" end)
        |> ExEval.put_judge(ExEval.BroadcasterTest.MockJudge)
        |> ExEval.put_reporter(SilentReporter)

      # Run async
      {:ok, run_id} = run_with_captured_logs(config, async: true)

      # Collect events with longer timeout for async runs
      events = collect_broadcast_events(broadcaster_name, [], 1000)
      assert length(events) >= 3

      # Verify run_id is consistent across events
      run_ids = events |> Enum.map(& &1.data.run_id) |> Enum.uniq()
      assert length(run_ids) == 1
      assert hd(run_ids) == run_id
    end
  end
end
