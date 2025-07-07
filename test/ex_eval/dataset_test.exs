# Define test modules outside of the test module to avoid protocol consolidation issues
defmodule ExEval.DatasetTest.CustomDataset do
  defstruct [:cases, :response_fn, :metadata, :setup_fn, :judge, :config]
end

# Implement the Dataset protocol for our custom struct
defimpl ExEval.Dataset, for: ExEval.DatasetTest.CustomDataset do
  def cases(%ExEval.DatasetTest.CustomDataset{cases: cases}), do: cases || []
  def response_fn(%ExEval.DatasetTest.CustomDataset{response_fn: func}), do: func
  def metadata(%ExEval.DatasetTest.CustomDataset{metadata: meta}), do: meta || %{}
  def setup_fn(%ExEval.DatasetTest.CustomDataset{setup_fn: func}), do: func

  def judge_config(%ExEval.DatasetTest.CustomDataset{judge: judge, config: config}) do
    %{
      judge: judge,
      config: config || %{}
    }
  end
end

# Define a test judge module
defmodule ExEval.DatasetTest.DatasetTestJudge do
  @behaviour ExEval.Judge

  @impl true
  def call(_response, _criteria, config) do
    # Return result based on config to verify it's passed through
    case config[:test_mode] do
      :pass -> {:ok, true, %{reasoning: "Dataset judge passed"}}
      :fail -> {:ok, false, %{reasoning: "Dataset judge failed"}}
      _ -> {:ok, true, %{reasoning: "Default pass"}}
    end
  end
end

defmodule ExEval.DatasetTest do
  use ExUnit.Case
  alias ExEval.SilentReporter

  describe "Dataset protocol for Map" do
    test "cases/1 returns cases when present" do
      dataset = %{
        cases: [
          %{input: "test1", judge_prompt: "Is it good?", category: :test},
          %{input: "test2", judge_prompt: "Is it bad?", category: :test}
        ]
      }

      cases = ExEval.Dataset.cases(dataset)
      assert length(cases) == 2
      assert List.first(cases).input == "test1"
    end

    test "cases/1 returns empty list when no cases key" do
      dataset = %{other: "data"}
      assert ExEval.Dataset.cases(dataset) == []
    end

    test "response_fn/1 returns function when present" do
      response_fn = fn input -> "Response to: #{input}" end
      dataset = %{response_fn: response_fn}

      retrieved_fn = ExEval.Dataset.response_fn(dataset)
      assert is_function(retrieved_fn, 1)
      assert retrieved_fn.("hello") == "Response to: hello"
    end

    test "response_fn/1 returns default function when not present" do
      dataset = %{other: "data"}
      retrieved_fn = ExEval.Dataset.response_fn(dataset)

      assert is_function(retrieved_fn, 1)
      assert retrieved_fn.("anything") == "No response function defined"
    end

    test "metadata/1 returns metadata when present" do
      dataset = %{
        metadata: %{name: "Test Dataset", version: "1.0"}
      }

      metadata = ExEval.Dataset.metadata(dataset)
      assert metadata.name == "Test Dataset"
      assert metadata.version == "1.0"
    end

    test "metadata/1 returns the whole map when no metadata key" do
      dataset = %{name: "Direct", other: "data"}
      metadata = ExEval.Dataset.metadata(dataset)

      assert metadata.name == "Direct"
      assert metadata.other == "data"
    end

    test "setup_fn/1 returns function when present" do
      setup_fn = fn -> %{context: "test"} end
      dataset = %{setup_fn: setup_fn}

      retrieved_fn = ExEval.Dataset.setup_fn(dataset)
      assert is_function(retrieved_fn, 0)
      assert retrieved_fn.() == %{context: "test"}
    end

    test "setup_fn/1 returns nil when not present" do
      dataset = %{other: "data"}
      assert ExEval.Dataset.setup_fn(dataset) == nil
    end

    test "judge_config/1 returns judge and config when present" do
      dataset = %{
        judge: MyApp.CustomJudge,
        config: %{model: "gpt-4", temperature: 0.0}
      }

      judge_config = ExEval.Dataset.judge_config(dataset)
      assert judge_config.judge == MyApp.CustomJudge
      assert judge_config.config == %{model: "gpt-4", temperature: 0.0}
    end

    test "judge_config/1 returns nil judge when not present" do
      dataset = %{other: "data"}
      judge_config = ExEval.Dataset.judge_config(dataset)

      assert judge_config.judge == nil
      assert judge_config.config == %{}
    end

    test "judge_config/1 returns empty config when only judge is present" do
      dataset = %{judge: MyApp.CustomJudge}
      judge_config = ExEval.Dataset.judge_config(dataset)

      assert judge_config.judge == MyApp.CustomJudge
      assert judge_config.config == %{}
    end
  end

  describe "Dataset protocol with custom implementation" do
    alias ExEval.DatasetTest.CustomDataset
    alias ExEval.DatasetTest.DatasetTestJudge

    setup %{test: test_name} do
      # Create unique names for this test
      registry_name = :"#{test_name}_registry"
      supervisor_name = :"#{test_name}_supervisor"

      # Start test-specific processes
      start_supervised!({Registry, keys: :unique, name: registry_name})
      start_supervised!({DynamicSupervisor, name: supervisor_name, strategy: :one_for_one})

      {:ok, registry: registry_name, supervisor: supervisor_name}
    end

    test "custom dataset with judge configuration", %{
      registry: _registry,
      supervisor: _supervisor
    } do
      # Create a custom dataset with its own judge
      custom_dataset = %CustomDataset{
        cases: [
          %{input: "test", judge_prompt: "Is this good?", category: :test}
        ],
        response_fn: fn _input -> "test response" end,
        judge: DatasetTestJudge,
        config: %{test_mode: :pass},
        metadata: %{source: :custom}
      }

      # Note: For custom datasets, we need to handle them differently
      # The inline configuration expects just cases, not full dataset objects
      # This is a limitation of the current architecture

      # Instead, let's test the protocol directly
      assert ExEval.Dataset.cases(custom_dataset) == [
               %{input: "test", judge_prompt: "Is this good?", category: :test}
             ]

      judge_config = ExEval.Dataset.judge_config(custom_dataset)
      assert judge_config.judge == DatasetTestJudge
      assert judge_config.config == %{test_mode: :pass}

      response_fn = ExEval.Dataset.response_fn(custom_dataset)
      assert response_fn.("hello") == "test response"

      metadata = ExEval.Dataset.metadata(custom_dataset)
      assert metadata.source == :custom
    end
  end

  describe "Dataset protocol integration with inline configuration" do
    setup %{test: test_name} do
      # Create unique names for this test
      registry_name = :"#{test_name}_registry"
      supervisor_name = :"#{test_name}_supervisor"

      # Start test-specific processes
      start_supervised!({Registry, keys: :unique, name: registry_name})
      start_supervised!({DynamicSupervisor, name: supervisor_name, strategy: :one_for_one})

      {:ok, registry: registry_name, supervisor: supervisor_name}
    end

    test "inline configuration creates proper dataset", %{
      registry: registry,
      supervisor: supervisor
    } do
      # Define a simple judge
      defmodule SimpleJudge do
        @behaviour ExEval.Judge

        @impl true
        def call(_response, _criteria, _config) do
          {:ok, true, %{reasoning: "Test passed"}}
        end
      end

      cases = [
        %{input: "test1", judge_prompt: "Is this good?", category: :test},
        %{input: "test2", judge_prompt: "Is this bad?", category: :test}
      ]

      response_fn = fn input -> "Response to: #{input}" end

      config =
        ExEval.new()
        |> ExEval.put_judge(SimpleJudge)
        |> ExEval.put_dataset(cases)
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor,
          reporter: SilentReporter
        )

      assert result.status == :completed
      assert length(result.results) == 2
      assert result.metadata.experiment == nil

      # Check that inline config creates proper dataset metadata
      first_result = List.first(result.results)
      assert first_result.dataset.type == :inline
      assert first_result.dataset.source == :config
    end

    test "runner raises error when no judge is configured", %{
      registry: registry,
      supervisor: supervisor
    } do
      cases = [
        %{input: "test", judge_prompt: "Is this good?", category: :test}
      ]

      config =
        ExEval.new()
        # Don't set any judge
        |> ExEval.put_dataset(cases)
        |> ExEval.put_response_fn(fn input -> "Response: #{input}" end)
        |> ExEval.put_reporter(SilentReporter)

      # The runner will encounter the error during execution
      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor,
          timeout: 5000
        )

      # The run completes but individual results have errors
      assert result.status == :completed
      assert length(result.results) == 1

      # Check that the individual result has an error
      eval_result = List.first(result.results)
      assert eval_result.status == :error
      assert eval_result.error =~ "No judge configured"
    end

    test "response function arity handling", %{
      registry: registry,
      supervisor: supervisor
    } do
      defmodule ArityTestJudge do
        @behaviour ExEval.Judge

        @impl true
        def call(response, _criteria, _config) do
          if String.contains?(response, "Context:") do
            {:ok, true, %{reasoning: "Response used context"}}
          else
            {:ok, false, %{reasoning: "Response did not use context"}}
          end
        end
      end

      cases = [
        %{input: "test", judge_prompt: "Does response use context?", category: :test}
      ]

      # Test with arity-2 response function (input, context)
      # The inline config doesn't support setup_fn, so context will be empty map
      response_fn = fn input, context ->
        "Input: #{input}, Context: #{inspect(context)}"
      end

      config =
        ExEval.new()
        |> ExEval.put_judge(ArityTestJudge)
        |> ExEval.put_dataset(cases)
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.Runner.run_sync(config,
          registry: registry,
          supervisor: supervisor
        )

      assert result.status == :completed
      eval_result = List.first(result.results)
      assert eval_result.status == :passed
      assert eval_result.reasoning == "Response used context"
    end
  end
end
