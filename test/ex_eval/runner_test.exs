defmodule ExEval.RunnerTest do
  use ExUnit.Case, async: true

  setup %{test: test_name} do
    # Create unique names for this test
    registry_name = :"#{test_name}_registry"
    supervisor_name = :"#{test_name}_supervisor"
    pubsub_name = :"#{test_name}_pubsub"

    # Start test-specific processes
    start_supervised!({Registry, keys: :unique, name: registry_name})
    start_supervised!({DynamicSupervisor, name: supervisor_name, strategy: :one_for_one})
    start_supervised!({Phoenix.PubSub, name: pubsub_name})

    # Return the names in the context for the tests to use
    {:ok, registry: registry_name, supervisor: supervisor_name, pubsub: pubsub_name}
  end

  defmodule TestEval do
    use ExEval.DatasetProvider.Module,
      judge_provider: ExEval.JudgeProvider.TestMock,
      config: %{mock_response: "YES\nTest response looks good"}

    def response_fn(input) do
      case input do
        "test1" -> "response1"
        "test2" -> "response2"
        _ -> "default response"
      end
    end

    eval_dataset [
      %{
        input: "test1",
        judge_prompt: "Does the response contain 'response1'?",
        category: "basic"
      },
      %{
        input: "test2",
        judge_prompt: "Does the response contain 'response2'?",
        category: "advanced"
      }
    ]
  end

  describe "run_sync/2" do
    test "runs evaluation synchronously and returns results", %{
      registry: registry,
      supervisor: supervisor,
      pubsub: pubsub
    } do
      result =
        ExEval.Runner.run_sync([TestEval],
          registry: registry,
          supervisor: supervisor,
          pubsub: pubsub,
          reporter: ExEval.Reporter.Silent
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
      supervisor: supervisor,
      pubsub: pubsub
    } do
      result =
        ExEval.Runner.run_sync([TestEval],
          categories: ["basic"],
          registry: registry,
          supervisor: supervisor,
          pubsub: pubsub,
          reporter: ExEval.Reporter.Silent
        )

      assert length(result.results) == 1
      assert List.first(result.results).category == "basic"
    end

    test "supports sequential execution", %{
      registry: registry,
      supervisor: supervisor,
      pubsub: pubsub
    } do
      result =
        ExEval.Runner.run_sync([TestEval],
          parallel: false,
          registry: registry,
          supervisor: supervisor,
          pubsub: pubsub,
          reporter: ExEval.Reporter.Silent
        )

      assert result.status == :completed
      assert length(result.results) == 2
    end
  end

  describe "run/2 async" do
    test "starts evaluation asynchronously and returns run_id", %{
      registry: registry,
      supervisor: supervisor,
      pubsub: pubsub
    } do
      {:ok, run_id} =
        ExEval.Runner.run([TestEval],
          registry: registry,
          supervisor: supervisor,
          pubsub: pubsub,
          reporter: ExEval.Reporter.Silent
        )

      assert is_binary(run_id)

      # For async runs, we need to handle the fact that the process might complete quickly
      # Let's use subscribe to get updates
      ExEval.Runner.subscribe(run_id, pubsub: pubsub)

      # Wait for completion message
      assert_receive {:runner_update, ^run_id, %{status: :completed} = final_state}, 5000
      assert length(final_state.results) == 2
    end

    test "can query run status during execution", %{
      registry: registry,
      supervisor: supervisor,
      pubsub: pubsub
    } do
      {:ok, run_id} =
        ExEval.Runner.run([TestEval],
          registry: registry,
          supervisor: supervisor,
          pubsub: pubsub,
          reporter: ExEval.Reporter.Silent
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

  describe "Dataset protocol" do
    test "works with module-based datasets" do
      cases = ExEval.Dataset.cases(TestEval)
      assert length(cases) == 2

      response_fn = ExEval.Dataset.response_fn(TestEval)
      assert is_function(response_fn)
      assert response_fn.("test1") == "response1"

      metadata = ExEval.Dataset.metadata(TestEval)
      assert metadata.module == TestEval
    end

    test "works with map-based datasets" do
      map_dataset = %{
        cases: [%{input: "test", judge_prompt: "Is this a test?"}],
        response_fn: fn input -> "response for #{input}" end,
        metadata: %{name: "test dataset"}
      }

      cases = ExEval.Dataset.cases(map_dataset)
      assert length(cases) == 1

      response_fn = ExEval.Dataset.response_fn(map_dataset)
      assert response_fn.("hello") == "response for hello"

      metadata = ExEval.Dataset.metadata(map_dataset)
      assert metadata.name == "test dataset"
    end
  end
end
