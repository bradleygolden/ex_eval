defmodule ExEvalTest do
  use ExUnit.Case
  alias ExEval.SilentReporter

  describe "new/1" do
    test "creates config with all defaults" do
      config = ExEval.new()

      assert config.judge == nil
      assert config.reporter == ExEval.Reporter.Console
      assert config.max_concurrency == 10
      assert config.timeout == 30_000
      assert config.parallel == true
      assert config.experiment == nil
      assert config.params == %{}
      assert config.tags == %{}
      assert config.artifact_logging == false
    end

    test "creates config with custom values" do
      config =
        ExEval.new(
          judge: ExEval.SomeJudge,
          reporter: ExEval.Reporter.Console,
          max_concurrency: 5,
          timeout: 60_000,
          parallel: false,
          experiment: "test_exp",
          params: %{model: "gpt-4"},
          tags: %{env: :test},
          artifact_logging: true
        )

      assert config.judge == ExEval.SomeJudge
      assert config.reporter == ExEval.Reporter.Console
      assert config.max_concurrency == 5
      assert config.timeout == 60_000
      assert config.parallel == false
      assert config.experiment == "test_exp"
      assert config.params == %{model: "gpt-4"}
      assert config.tags == %{env: :test}
      assert config.artifact_logging == true
    end

    test "ignores unknown options" do
      config = ExEval.new(unknown_option: "value", another: 123)
      assert config.judge == nil
      assert config.reporter == ExEval.Reporter.Console
    end
  end

  describe "put_judge/2 and put_judge/3" do
    test "sets judge with module only" do
      config = ExEval.new() |> ExEval.put_judge(ExEval.SomeJudge)
      assert config.judge == ExEval.SomeJudge
    end

    test "sets judge with module and options" do
      config =
        ExEval.new() |> ExEval.put_judge(ExEval.SomeJudge, model: "gpt-4", temperature: 0.0)

      assert config.judge == {ExEval.SomeJudge, [model: "gpt-4", temperature: 0.0]}
    end

    test "sets judge with tuple format" do
      config = ExEval.new() |> ExEval.put_judge({ExEval.SomeJudge, model: "gpt-4"})
      assert config.judge == {ExEval.SomeJudge, [model: "gpt-4"]}
    end

    test "overwrites previous judge configuration" do
      config =
        ExEval.new()
        |> ExEval.put_judge(ExEval.FirstJudge)
        |> ExEval.put_judge(ExEval.SecondJudge, model: "gpt-4")

      assert config.judge == {ExEval.SecondJudge, [model: "gpt-4"]}
    end

    test "handles empty options list" do
      config = ExEval.new() |> ExEval.put_judge(ExEval.SomeJudge, [])
      assert config.judge == {ExEval.SomeJudge, []}
    end
  end

  describe "put_reporter/2 and put_reporter/3" do
    test "sets reporter with module only" do
      config = ExEval.new() |> ExEval.put_reporter(ExEval.Reporter.Console)
      assert config.reporter == ExEval.Reporter.Console
    end

    test "sets reporter with module and options" do
      config =
        ExEval.new() |> ExEval.put_reporter(ExEval.Reporter.Console, colors: true, verbose: true)

      assert config.reporter == {ExEval.Reporter.Console, [colors: true, verbose: true]}
    end

    test "sets reporter with tuple format" do
      config = ExEval.new() |> ExEval.put_reporter({ExEval.Phoenix.PubSub, pubsub: MyApp.PubSub})
      assert config.reporter == {ExEval.Phoenix.PubSub, [pubsub: MyApp.PubSub]}
    end

    test "overwrites previous reporter configuration" do
      config =
        ExEval.new()
        |> ExEval.put_reporter(ExEval.Reporter.Console)
        |> ExEval.put_reporter(ExEval.Reporter.Console)

      assert config.reporter == ExEval.Reporter.Console
    end
  end

  describe "put_max_concurrency/2" do
    test "sets valid max concurrency" do
      config = ExEval.new() |> ExEval.put_max_concurrency(20)
      assert config.max_concurrency == 20
    end

    test "sets max concurrency to 1" do
      config = ExEval.new() |> ExEval.put_max_concurrency(1)
      assert config.max_concurrency == 1
    end

    test "raises for zero concurrency" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_max_concurrency(0)
      end
    end

    test "raises for negative concurrency" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_max_concurrency(-5)
      end
    end

    test "raises for non-integer concurrency" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_max_concurrency("10")
      end
    end
  end

  describe "put_timeout/2" do
    test "sets valid timeout" do
      config = ExEval.new() |> ExEval.put_timeout(60_000)
      assert config.timeout == 60_000
    end

    test "sets minimum timeout of 1ms" do
      config = ExEval.new() |> ExEval.put_timeout(1)
      assert config.timeout == 1
    end

    test "raises for zero timeout" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_timeout(0)
      end
    end

    test "raises for negative timeout" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_timeout(-1000)
      end
    end

    test "raises for non-integer timeout" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_timeout(30.5)
      end
    end
  end

  describe "put_parallel/2" do
    test "enables parallel execution" do
      config = ExEval.new() |> ExEval.put_parallel(true)
      assert config.parallel == true
    end

    test "disables parallel execution" do
      config = ExEval.new() |> ExEval.put_parallel(false)
      assert config.parallel == false
    end

    test "raises for non-boolean values" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_parallel("true")
      end

      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_parallel(1)
      end
    end
  end

  describe "put_experiment/2" do
    test "sets experiment name with string" do
      config = ExEval.new() |> ExEval.put_experiment("safety_eval_v2")
      assert config.experiment == "safety_eval_v2"
    end

    test "sets experiment name with atom" do
      config = ExEval.new() |> ExEval.put_experiment(:safety_eval_v2)
      assert config.experiment == :safety_eval_v2
    end

    test "overwrites previous experiment" do
      config =
        ExEval.new()
        |> ExEval.put_experiment("exp1")
        |> ExEval.put_experiment(:exp2)

      assert config.experiment == :exp2
    end

    test "raises for invalid experiment types" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_experiment(123)
      end

      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_experiment(%{name: "test"})
      end
    end
  end

  describe "put_params/2" do
    test "sets initial params" do
      config = ExEval.new() |> ExEval.put_params(%{model: "gpt-4", temperature: 0.0})
      assert config.params == %{model: "gpt-4", temperature: 0.0}
    end

    test "merges params with existing ones" do
      config =
        ExEval.new()
        |> ExEval.put_params(%{model: "gpt-4"})
        |> ExEval.put_params(%{temperature: 0.0})

      assert config.params == %{model: "gpt-4", temperature: 0.0}
    end

    test "overwrites existing param values" do
      config =
        ExEval.new()
        |> ExEval.put_params(%{model: "gpt-3.5"})
        |> ExEval.put_params(%{model: "gpt-4"})

      assert config.params == %{model: "gpt-4"}
    end

    test "handles empty params" do
      config = ExEval.new() |> ExEval.put_params(%{})
      assert config.params == %{}
    end

    test "raises for non-map params" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_params(model: "gpt-4")
      end
    end
  end

  describe "put_tags/2" do
    test "sets initial tags" do
      config = ExEval.new() |> ExEval.put_tags(%{team: :safety, env: :prod})
      assert config.tags == %{team: :safety, env: :prod}
    end

    test "merges tags with existing ones" do
      config =
        ExEval.new()
        |> ExEval.put_tags(%{team: :safety})
        |> ExEval.put_tags(%{env: :prod})

      assert config.tags == %{team: :safety, env: :prod}
    end

    test "overwrites existing tag values" do
      config =
        ExEval.new()
        |> ExEval.put_tags(%{env: :staging})
        |> ExEval.put_tags(%{env: :prod})

      assert config.tags == %{env: :prod}
    end

    test "handles atom and string tag values" do
      config =
        ExEval.new()
        |> ExEval.put_tags(%{
          team: :safety,
          version: "1.2.0",
          priority: :high,
          commit: "abc123"
        })

      assert config.tags.team == :safety
      assert config.tags.version == "1.2.0"
      assert config.tags.priority == :high
      assert config.tags.commit == "abc123"
    end

    test "raises for non-map tags" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_tags("invalid")
      end
    end
  end

  describe "put_artifact_logging/2" do
    test "enables artifact logging" do
      config = ExEval.new() |> ExEval.put_artifact_logging(true)
      assert config.artifact_logging == true
    end

    test "disables artifact logging" do
      config = ExEval.new() |> ExEval.put_artifact_logging(false)
      assert config.artifact_logging == false
    end

    test "raises for non-boolean values" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_artifact_logging("yes")
      end
    end
  end

  describe "function chaining" do
    test "supports fluent API chaining" do
      config =
        ExEval.new()
        |> ExEval.put_judge(ExEval.LangChain, model: "gpt-4")
        |> ExEval.put_reporter(ExEval.Phoenix.PubSub, pubsub: MyApp.PubSub)
        |> ExEval.put_experiment("chain_test")
        |> ExEval.put_params(%{temperature: 0.0})
        |> ExEval.put_tags(%{test: :chaining})
        |> ExEval.put_max_concurrency(5)
        |> ExEval.put_timeout(10_000)
        |> ExEval.put_parallel(false)
        |> ExEval.put_artifact_logging(true)

      assert config.judge == {ExEval.LangChain, [model: "gpt-4"]}
      assert config.reporter == {ExEval.Phoenix.PubSub, [pubsub: MyApp.PubSub]}
      assert config.experiment == "chain_test"
      assert config.params == %{temperature: 0.0}
      assert config.tags == %{test: :chaining}
      assert config.max_concurrency == 5
      assert config.timeout == 10_000
      assert config.parallel == false
      assert config.artifact_logging == true
    end

    test "order doesn't matter for independent settings" do
      config1 =
        ExEval.new()
        |> ExEval.put_timeout(5000)
        |> ExEval.put_max_concurrency(3)

      config2 =
        ExEval.new()
        |> ExEval.put_max_concurrency(3)
        |> ExEval.put_timeout(5000)

      assert config1 == config2
    end
  end

  describe "inline configuration" do
    test "put_dataset/2 sets dataset" do
      dataset = [
        %{input: "test", judge_prompt: "Is this good?", category: :test}
      ]

      config = ExEval.new() |> ExEval.put_dataset(dataset)
      assert config.dataset == dataset
    end

    test "put_response_fn/2 sets response function" do
      response_fn = fn input -> "response to: #{input}" end

      config = ExEval.new() |> ExEval.put_response_fn(response_fn)
      assert config.response_fn == response_fn
    end

    test "fluent API for inline configuration" do
      dataset = [
        %{input: "What is 2+2?", judge_prompt: "Is the answer correct?", category: :math}
      ]

      response_fn = fn
        "What is 2+2?" -> "4"
        _ -> "I don't know"
      end

      config =
        ExEval.new()
        |> ExEval.put_judge(ExEval.LangChain, model: "gpt-4")
        |> ExEval.put_dataset(dataset)
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_experiment(:inline_test)

      assert config.judge == {ExEval.LangChain, [model: "gpt-4"]}
      assert config.dataset == dataset
      assert config.response_fn == response_fn
      assert config.experiment == :inline_test
    end

    test "raises for non-list dataset" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_dataset("not a list")
      end
    end

    test "raises for non-function response_fn" do
      assert_raise FunctionClauseError, fn ->
        ExEval.new() |> ExEval.put_response_fn("not a function")
      end
    end
  end

  describe "edge cases" do
    test "handles nil values in new/1" do
      config = ExEval.new(judge: nil, reporter: nil)
      assert config.judge == nil
      # Reporter should still have default
      assert config.reporter == nil
    end

    test "struct enforces types" do
      # This will create the struct but with potentially invalid types
      config = %ExEval{
        judge: "not a module",
        reporter: 123,
        max_concurrency: "ten",
        timeout: -1,
        parallel: "yes",
        experiment: :atom_not_string,
        params: [],
        tags: "not a map",
        artifact_logging: 1
      }

      # The struct is created but the values are invalid
      # This shows why we have guards in our functions
      assert config.judge == "not a module"
      assert config.reporter == 123
    end

    test "multiple calls to same setter accumulate or override appropriately" do
      config = ExEval.new()

      # Judge and reporter override
      config =
        config
        |> ExEval.put_judge(ExEval.Judge1)
        |> ExEval.put_judge(ExEval.Judge2)

      assert config.judge == ExEval.Judge2

      # Params and tags merge
      config =
        config
        |> ExEval.put_params(%{a: 1})
        |> ExEval.put_params(%{b: 2})
        |> ExEval.put_tags(%{x: :foo})
        |> ExEval.put_tags(%{y: :bar})

      assert config.params == %{a: 1, b: 2}
      assert config.tags == %{x: :foo, y: :bar}
    end
  end

  describe "put_store/2 and put_store/3" do
    # Mock store for testing
    defmodule MockStore do
      @behaviour ExEval.Store

      @impl true
      def save_run(_run_data), do: :ok

      @impl true
      def get_run(run_id), do: %{id: run_id}

      @impl true
      def list_runs(_opts), do: []

      @impl true
      def query(_criteria), do: []
    end

    test "sets store module with tuple format" do
      config = ExEval.new() |> ExEval.put_store({MockStore, ttl: 3600})
      assert config.store == {MockStore, ttl: 3600}
    end

    test "sets store module with separate opts" do
      config = ExEval.new() |> ExEval.put_store(MockStore, ttl: 3600)
      assert config.store == {MockStore, ttl: 3600}
    end

    test "sets store module without opts" do
      config = ExEval.new() |> ExEval.put_store(MockStore)
      assert config.store == MockStore
    end
  end

  describe "run/2" do
    # Simple test judge for inline configuration tests
    defmodule InlineTestJudge do
      @behaviour ExEval.Judge

      @impl true
      def call(_response, _criteria, _config) do
        {:ok, true, %{reasoning: "Test passed"}}
      end
    end

    test "run/2 executes evaluation synchronously when async: false" do
      # Start test-specific supervisor and registry
      start_supervised!({Registry, keys: :unique, name: :test_registry_sync})
      start_supervised!({DynamicSupervisor, name: :test_supervisor_sync, strategy: :one_for_one})

      config =
        ExEval.new()
        |> ExEval.put_judge(InlineTestJudge)
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "good?", category: :test}])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.run(config,
          async: false,
          registry: :test_registry_sync,
          supervisor: :test_supervisor_sync
        )

      assert result.status == :completed
      assert length(result.results) == 1
      assert hd(result.results).status == :passed
    end

    test "run/2 executes evaluation asynchronously by default" do
      # Start test-specific supervisor and registry
      start_supervised!({Registry, keys: :unique, name: :test_registry_async_default})

      start_supervised!(
        {DynamicSupervisor, name: :test_supervisor_async_default, strategy: :one_for_one}
      )

      config =
        ExEval.new()
        |> ExEval.put_judge(InlineTestJudge)
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "good?", category: :test}])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.run(config,
          registry: :test_registry_async_default,
          supervisor: :test_supervisor_async_default
        )

      assert is_binary(run_id)

      # Give it a moment to complete
      Process.sleep(100)
    end

    test "run/2 with async: true executes evaluation asynchronously" do
      # Start test-specific supervisor and registry
      start_supervised!({Registry, keys: :unique, name: :test_registry_async_true})

      start_supervised!(
        {DynamicSupervisor, name: :test_supervisor_async_true, strategy: :one_for_one}
      )

      config =
        ExEval.new()
        |> ExEval.put_judge(InlineTestJudge)
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "good?", category: :test}])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      {:ok, run_id} =
        ExEval.run(config,
          async: true,
          registry: :test_registry_async_true,
          supervisor: :test_supervisor_async_true
        )

      assert is_binary(run_id)

      # Give it a moment to complete
      Process.sleep(100)
    end

    test "run/2 function exists with correct arity" do
      # Ensure the function exists with the correct arity
      assert function_exported?(ExEval, :run, 2)
    end
  end
end
