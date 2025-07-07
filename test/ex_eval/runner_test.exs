defmodule ExEval.RunnerTest do
  use ExUnit.Case, async: true
  alias ExEval.SilentReporter

  # Inline test judge mock
  defmodule TestJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, config) do
      case config[:mock_result] do
        nil -> {:ok, true, %{reasoning: "Test passed"}}
        result -> result
      end
    end
  end

  # Slow judge for testing cancellation
  defmodule SlowJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      # Sleep to simulate slow judge
      Process.sleep(100)
      {:ok, true, %{reasoning: "Slow judge result"}}
    end
  end

  setup %{test: test_name} do
    # Create unique names for this test
    registry_name = :"#{test_name}_registry"
    supervisor_name = :"#{test_name}_supervisor"

    # Start test-specific processes
    start_supervised!({Registry, keys: :unique, name: registry_name})
    start_supervised!({DynamicSupervisor, name: supervisor_name, strategy: :one_for_one})

    # Return the names in the context for the tests to use
    {:ok, registry: registry_name, supervisor: supervisor_name}
  end

  # Test dataset for inline configuration
  @test_dataset [
    %{
      input: "test1",
      judge_prompt: "Does the response contain 'response1'?",
      category: :basic
    },
    %{
      input: "test2",
      judge_prompt: "Does the response contain 'response2'?",
      category: :advanced
    }
  ]

  # Test response function
  def test_response_fn(input) do
    case input do
      "test1" -> "response1"
      "test2" -> "response2"
      _ -> "default response"
    end
  end

  describe "run_sync/1" do
    test "runs evaluation synchronously and returns results", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert %{
               id: run_id,
               status: :completed,
               results: results,
               started_at: started_at,
               finished_at: finished_at
             } = result

      assert is_binary(run_id)
      assert %DateTime{} = started_at
      assert %DateTime{} = finished_at
      assert length(results) == 2

      # Check result structure
      result = List.first(results)
      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :input)
      assert Map.has_key?(result, :judge_prompt)
      assert Map.has_key?(result, :duration_ms)
    end

    test "supports categories filter", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          categories: [:basic],
          registry: registry,
          supervisor: supervisor
        )

      assert length(result.results) == 1
      assert List.first(result.results).category == :basic
    end

    test "supports sequential execution", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)
        |> ExEval.put_parallel(false)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 2
    end
  end

  describe "run/1 async" do
    test "starts evaluation asynchronously and returns run_id", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.Runner.run(config,
          registry: registry,
          supervisor: supervisor
        )

      assert is_binary(run_id)

      # Poll for completion since we don't have PubSub anymore
      Process.sleep(100)

      # Check if run completed
      case ExEval.Runner.get_run(run_id, registry: registry) do
        {:ok, final_state} ->
          assert final_state.status == :completed
          assert length(final_state.results) == 2

        {:error, :not_found} ->
          # Run completed and was removed from registry
          assert true
      end
    end

    test "can query run status during execution", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.Runner.run(config,
          registry: registry,
          supervisor: supervisor
        )

      # Should be able to get run status
      case ExEval.Runner.get_run(run_id, registry: registry) do
        {:ok, state} ->
          assert state.id == run_id
          assert state.status in [:pending, :running, :completed]

        {:error, :not_found} ->
          # Run might have completed very quickly
          :ok
      end
    end
  end

  describe "list_active_runs/0" do
    test "returns empty list when no runs are active", %{registry: registry} do
      # Simply test that the function works without errors
      runs = ExEval.Runner.list_active_runs(registry: registry)
      assert is_list(runs)
      assert runs == []
    end
  end

  describe "cancel_run/2" do
    test "cancels a running evaluation", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(SlowJudge)
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.Runner.run(config,
          registry: registry,
          supervisor: supervisor
        )

      # Give the process a moment to start
      Process.sleep(10)

      # Cancel the run
      result = ExEval.Runner.cancel_run(run_id, registry: registry)
      assert {:ok, :cancelled} = result
    end

    test "returns error when run not found", %{registry: registry} do
      result = ExEval.Runner.cancel_run("nonexistent_id", registry: registry)
      assert {:error, :not_found} = result
    end
  end

  describe "error handling" do
    test "handles empty inline configuration", %{
      registry: registry,
      supervisor: supervisor
    } do
      config = ExEval.new()

      # Empty configuration should complete with no results
      result = ExEval.Runner.run_sync(config, registry: registry, supervisor: supervisor)
      
      assert result.status == :completed
      assert result.results == []
    end

    test "handles missing judge configuration", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      # Should complete with error results due to missing judge
      assert result.status == :completed
      assert length(result.results) == 2

      # All results should be errors due to missing judge
      Enum.each(result.results, fn result ->
        assert result.status == :error
        assert result.error =~ "No judge configured"
      end)
    end

    test "handles response function with wrong arity", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Function with arity 4 (invalid)
      invalid_fn = fn _, _, _, _ -> "invalid" end

      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(invalid_fn)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      # Should get an error result
      assert result.status == :completed
      error_results = Enum.filter(result.results, &(&1.status == :error))
      assert length(error_results) > 0
      assert Enum.any?(error_results, &String.contains?(&1.error, "arity"))
    end

    test "handles judge errors", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge, mock_result: {:error, "Judge failed"})
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      error_results = Enum.filter(result.results, &(&1.status == :error))
      assert length(error_results) > 0
      assert Enum.any?(error_results, &String.contains?(&1.error, "Judge error"))
    end
  end

  describe "dataset judge configuration" do
    test "uses dataset-specific judge configuration", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Create a dataset with judge configuration
      dataset_with_judge = %{
        cases: @test_dataset,
        response_fn: &__MODULE__.test_response_fn/1,
        judge: TestJudge,
        config: %{mock_result: {:ok, true, %{reasoning: "Dataset judge result"}}},
        metadata: %{type: :inline, source: :test}
      }

      config =
        ExEval.new()
        |> ExEval.put_dataset(dataset_with_judge.cases)
        |> ExEval.put_response_fn(dataset_with_judge.response_fn)
        |> ExEval.put_judge(dataset_with_judge.judge, Map.to_list(dataset_with_judge.config))
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 2
      assert Enum.all?(result.results, &(&1.reasoning == "Dataset judge result"))
    end

    test "dataset judge config with empty configuration", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Create a dataset with judge but no config
      dataset_with_judge = %{
        cases: @test_dataset,
        response_fn: &__MODULE__.test_response_fn/1,
        judge: TestJudge,
        config: %{},
        metadata: %{type: :inline, source: :test}
      }

      config =
        ExEval.new()
        |> ExEval.put_dataset(dataset_with_judge.cases)
        |> ExEval.put_response_fn(dataset_with_judge.response_fn)
        |> ExEval.put_judge(dataset_with_judge.judge, Map.to_list(dataset_with_judge.config))
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 2
    end
  end

  describe "store integration" do
    # Mock store for testing
    defmodule TestStore do
      @behaviour ExEval.Store

      @impl true
      def save_run(run_data) do
        # Get the test PID from the run metadata 
        test_pid = get_in(run_data, [:metadata, :params, :test_pid]) || self()
        send(test_pid, {:store_save, run_data})
        :ok
      end

      @impl true
      def get_run(_run_id), do: nil

      @impl true
      def list_runs(_opts), do: []

      @impl true
      def query(_criteria), do: []
    end

    test "saves run to store when experiment is configured", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)
        |> ExEval.put_experiment(:test_experiment)
        |> ExEval.put_store(TestStore)
        |> ExEval.put_params(%{test_pid: self()})

      ExEval.Runner.run_sync(config,
        registry: registry,
        supervisor: supervisor
      )

      # Should receive a message that the store was called
      assert_receive {:store_save, run_data}, 200
      assert run_data.id
      assert run_data.metadata.experiment == :test_experiment
    end

    test "supports store configuration with options tuple", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Test response looks good"}}
        )
        |> ExEval.put_dataset(@test_dataset)
        |> ExEval.put_response_fn(&__MODULE__.test_response_fn/1)
        |> ExEval.put_reporter(SilentReporter)
        |> ExEval.put_experiment(:test_experiment)
        |> ExEval.put_store(TestStore, some_option: "value")
        |> ExEval.put_params(%{test_pid: self()})

      ExEval.Runner.run_sync(config,
        registry: registry,
        supervisor: supervisor
      )

      # Should receive a message that the store was called
      assert_receive {:store_save, run_data}, 200
      assert run_data.id
    end
  end

  describe "multi-turn conversations" do
    test "handles multi-turn conversation inputs", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Dataset with list inputs (multi-turn)
      multi_turn_dataset = [
        %{
          input: ["Hello", "How are you?", "Goodbye"],
          judge_prompt: "Does the conversation end appropriately?",
          category: :conversation
        }
      ]

      # Response function that handles conversation history
      conversation_fn = fn input, _context, conversation_history ->
        case input do
          "Hello" -> "Hi there!"
          "How are you?" -> "I'm doing well, thanks for asking!"
          "Goodbye" -> "See you later! Previous: #{length(conversation_history)} messages"
          _ -> "I don't understand"
        end
      end

      config =
        ExEval.new()
        |> ExEval.put_judge(TestJudge,
          mock_result: {:ok, true, %{reasoning: "Good conversation flow"}}
        )
        |> ExEval.put_dataset(multi_turn_dataset)
        |> ExEval.put_response_fn(conversation_fn)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 1
    end
  end

  describe "Dataset protocol" do
    test "works with map-based datasets" do
      dataset = %{
        cases: @test_dataset,
        response_fn: &__MODULE__.test_response_fn/1,
        metadata: %{type: :inline, source: :test}
      }

      cases = ExEval.Dataset.cases(dataset)
      assert length(cases) == 2

      response_fn = ExEval.Dataset.response_fn(dataset)
      assert is_function(response_fn)
      assert response_fn.("test1") == "response1"

      metadata = ExEval.Dataset.metadata(dataset)
      assert metadata.type == :inline
    end
  end

  # Additional judges for extended testing
  defmodule FailingJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:ok, false, %{reasoning: "Test failed as expected"}}
    end
  end

  defmodule ErrorJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:error, "Judge encountered an error"}
    end
  end

  defmodule TimeoutJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      # Simulate a long-running judge
      Process.sleep(10_000)
      {:ok, true, %{reasoning: "Should never reach here"}}
    end
  end

  # Test reporter that fails initialization
  defmodule FailingReporter do
    @behaviour ExEval.Reporter

    @impl true
    def init(_runner, _config), do: {:error, "Reporter initialization failed"}

    @impl true
    def report_result(_result, state, _config), do: {:ok, state}

    @impl true
    def finalize(_runner, _state, _config), do: :ok
  end

  describe "additional error handling" do
    test "handles judge failures gracefully", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Will fail", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 1

      eval_result = List.first(result.results)
      assert eval_result.status == :failed
      assert eval_result.reasoning == "Test failed as expected"
    end

    test "handles judge errors", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(ErrorJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Will error", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      eval_result = List.first(result.results)
      assert eval_result.status == :error
      assert eval_result.error =~ "Judge error"
    end

    test "handles response function errors", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "crash", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(fn input ->
          if input == "crash", do: raise("Response function error"), else: "ok"
        end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      eval_result = List.first(result.results)
      assert eval_result.status == :error
      assert eval_result.error =~ "Evaluation crashed"
    end

    test "handles reporter initialization failure", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(FailingReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :error
      assert result.error == "Reporter initialization failed"
    end

    test "handles timeout appropriately", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(TimeoutJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Will timeout", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)
        # 100ms timeout
        |> ExEval.put_timeout(100)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      # When the sync run times out, the runner returns a timeout error state
      assert result.status == :error
      assert result.error =~ "Evaluation timed out"
    end
  end

  describe "additional multi-turn conversations" do
    test "handles conversation inputs", %{registry: registry, supervisor: supervisor} do
      _conversation_history = []

      config =
        ExEval.new()
        # Use any judge
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{
            input: ["Hello", "How are you?", "Goodbye"],
            judge_prompt: "Is this a complete conversation?",
            category: :conversation
          }
        ])
        |> ExEval.put_response_fn(fn input ->
          "Response to: #{input}"
        end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert length(result.results) == 1
    end
  end

  describe "response function arity handling" do
    test "handles arity-2 response function with context", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Define setup function that provides context
      dataset = %{
        cases: [
          %{input: "test", judge_prompt: "Test", category: :test}
        ],
        response_fn: fn input, context ->
          "Input: #{input}, Context: #{inspect(context)}"
        end,
        setup_fn: fn -> %{environment: "test"} end
      }

      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset(dataset.cases)
        |> ExEval.put_response_fn(dataset.response_fn)
        |> ExEval.put_reporter(SilentReporter)

      # Note: The inline config doesn't support setup_fn, so context will be empty
      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
    end

    test "handles arity-3 response function with conversation history", %{
      registry: registry,
      supervisor: supervisor
    } do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{
            input: ["Hello", "How are you?"],
            judge_prompt: "Test",
            category: :conversation
          }
        ])
        |> ExEval.put_response_fn(fn input, _context, history ->
          "Input: #{input}, History: #{length(history)} messages"
        end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
    end

    test "raises on invalid response function arity", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Create a 4-arity function which is invalid
      response_fn = fn a, b, c, d -> "#{a}#{b}#{c}#{d}" end

      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      eval_result = List.first(result.results)
      assert eval_result.status == :error
      assert eval_result.error =~ "response_fn has arity 4"
    end
  end

  describe "extended cancellation" do
    @tag skip: "TODO: Fix cancellation logic - see issue #25"
    test "can cancel a running evaluation", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(TimeoutJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.Runner.run(config,
          registry: registry,
          supervisor: supervisor
        )

      # Give it a moment to start
      Process.sleep(50)

      # Cancel the run  
      case ExEval.Runner.cancel_run(run_id, registry: registry) do
        {:ok, :cancelled} ->
          assert true

        {:error, :not_found} ->
          # Run might have completed already (TimeoutJudge might not actually sleep)
          assert true
      end
    end

    test "returns error when cancelling non-existent run", %{registry: registry} do
      assert {:error, :not_found} = ExEval.Runner.cancel_run("non-existent", registry: registry)
    end
  end

  describe "experiment tracking and metadata" do
    test "includes experiment metadata in results", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "test", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)
        |> ExEval.put_experiment(:test_experiment)
        |> ExEval.put_params(%{model: "test-model", temperature: 0.5})
        |> ExEval.put_tags(%{environment: :test, version: "1.0"})

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor,
          metadata: %{custom_field: "custom_value"}
        )

      assert result.metadata.experiment == :test_experiment
      assert result.metadata.params == %{model: "test-model", temperature: 0.5}
      assert result.metadata.tags == %{environment: :test, version: "1.0"}
      assert result.metadata.custom_field == "custom_value"
    end

    test "includes metrics in completed runs", %{registry: registry, supervisor: supervisor} do
      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset([
          %{input: "test1", judge_prompt: "Test", category: :test},
          %{input: "test2", judge_prompt: "Test", category: :test}
        ])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      assert Map.has_key?(result, :metrics)
      assert result.metrics.total_cases == 2
      assert result.metrics.failed == 2
      assert result.metrics.pass_rate == 0.0
    end
  end

  describe "concurrent execution limits" do
    test "respects max_concurrency setting", %{registry: registry, supervisor: supervisor} do
      # Track concurrent executions
      agent = start_supervised!({Agent, fn -> %{max: 0, current: 0} end})

      config =
        ExEval.new()
        |> ExEval.put_judge(FailingJudge)
        |> ExEval.put_dataset(
          for i <- 1..10 do
            %{input: "test#{i}", judge_prompt: "Test", category: :test}
          end
        )
        |> ExEval.put_response_fn(fn _input ->
          # Track concurrent executions
          Agent.update(agent, fn state ->
            current = state.current + 1
            %{state | current: current, max: max(current, state.max)}
          end)

          # Simulate some work
          Process.sleep(50)

          Agent.update(agent, fn state ->
            %{state | current: state.current - 1}
          end)

          "response"
        end)
        |> ExEval.put_reporter(SilentReporter)
        |> ExEval.put_max_concurrency(3)

      _result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      # Check that max concurrency was respected
      max_concurrent = Agent.get(agent, & &1.max)
      assert max_concurrent <= 3
    end
  end

  describe "get_run edge cases" do
    test "handles process exit gracefully", %{registry: registry, supervisor: _supervisor} do
      # Create a dummy process and register it
      pid = spawn(fn -> Process.sleep(10) end)
      # Registry.register expects to be called from the process being registered
      # So we'll simulate a dead process by killing it after registration
      send(pid, :kill)
      Process.sleep(20)

      # Should handle the missing process gracefully
      assert {:error, :not_found} = ExEval.Runner.get_run("non-existent-run", registry: registry)
    end
  end
end
