defmodule ExEvalTest do
  use ExUnit.Case

  alias ExEval.DatasetProvider.Module
  alias ExEval.DatasetProvider.TestMock

  defmodule TestEval do
    use ExEval.Dataset,
      response_fn: &__MODULE__.test_response/1

    eval_dataset [
      %{
        input: "test input 1",
        judge_prompt: "Does this work?",
        category: "basic"
      },
      %{
        input: "test input 2",
        judge_prompt: "Is this correct?",
        category: "advanced"
      }
    ]

    def test_response(_input), do: "test response"
  end

  describe "new/1" do
    test "creates evaluator with judge provider and config" do
      evaluator =
        ExEval.new(
          judge_provider: ExEval.JudgeProvider.TestMock,
          config: %{mock_response: "YES\nTest passed"}
        )

      assert %ExEval{} = evaluator
      assert evaluator.judge_provider == ExEval.JudgeProvider.TestMock
      assert evaluator.config == %{mock_response: "YES\nTest passed"}
    end

    test "requires judge provider" do
      assert_raise KeyError, fn ->
        ExEval.new(config: %{})
      end
    end

    test "defaults config to empty map" do
      evaluator = ExEval.new(judge_provider: ExEval.JudgeProvider.TestMock)
      assert evaluator.config == %{}
    end
  end

  describe "API functions with TestMock" do
    test "list_evaluations/2 delegates to specified provider" do
      evaluations = ExEval.list_evaluations(TestMock, [])
      direct_evaluations = TestMock.list_evaluations([])

      assert evaluations == direct_evaluations
      assert evaluations == [:test_eval, :security_eval, :performance_eval]
    end

    test "get_evaluation_info/3 delegates to specified provider" do
      result = ExEval.get_evaluation_info(:test_eval, TestMock)
      direct_result = TestMock.get_evaluation_info(:test_eval)

      assert result == direct_result
      assert {:ok, info} = result
      assert info.module == :test_eval
      assert info.case_count == 2
      assert info.categories == ["basic", "advanced"]
    end

    test "get_evaluation_info/3 returns error for invalid evaluation" do
      result = ExEval.get_evaluation_info(:invalid, TestMock)
      assert {:error, :not_an_evaluation_module} = result
    end

    test "get_categories/2 delegates to specified provider" do
      categories = ExEval.get_categories(TestMock, [])
      direct_categories = TestMock.get_categories([])

      assert categories == direct_categories
      assert categories == ["advanced", "basic", "performance", "security"]
    end

    test "list_evaluations_by_category/3 delegates to specified provider" do
      security_evals = ExEval.list_evaluations_by_category(["security"], TestMock)
      assert security_evals == [:security_eval]

      basic_evals = ExEval.list_evaluations_by_category(["basic"], TestMock)
      assert basic_evals == [:test_eval]

      multi_evals = ExEval.list_evaluations_by_category(["security", "performance"], TestMock)
      assert :security_eval in multi_evals
      assert :performance_eval in multi_evals
      refute :test_eval in multi_evals
    end

    test "run_evaluation/1 with TestMock and TestReporter" do
      opts = %{
        provider: TestMock,
        evaluations: [:test_eval],
        judge_provider: ExEval.JudgeProvider.TestMock,
        judge_provider_config: %{mock_response: "YES\nTest passes"},
        reporter: ExEval.Reporter.TestMock,
        reporter_opts: [test_pid: self()]
      }

      assert {:ok, results} = ExEval.run_evaluation(opts)

      assert results.total == 2
      assert is_integer(results.passed)
      assert is_integer(results.failed)
      assert is_integer(results.errors)
      assert is_list(results.results)

      assert_receive {:eval_started, start_info}
      assert start_info.total_count == 1
      assert is_integer(start_info.seed)

      assert_receive {:eval_result, result1}
      assert_receive {:eval_result, result2}

      assert result1.input in ["test input 1", "test input 2"]
      assert result2.input in ["test input 1", "test input 2"]

      assert_receive {:eval_finished, finish_info}
      assert finish_info.total == 2
      assert is_integer(finish_info.duration_ms)
      assert length(finish_info.results) == 2
    end

    test "run_single_evaluation/2 with TestMock" do
      opts = %{
        provider: TestMock,
        judge_provider: ExEval.JudgeProvider.TestMock,
        judge_provider_config: %{mock_response: "YES\nTest passes"},
        reporter: ExEval.Reporter.TestMock,
        reporter_opts: [test_pid: self()]
      }

      assert {:ok, results} = ExEval.run_single_evaluation(:security_eval, opts)
      assert results.total == 1

      assert_receive {:eval_started, _}
      assert_receive {:eval_result, _}
      assert_receive {:eval_finished, _}
    end

    test "run_by_category/2 with TestMock" do
      opts = %{
        provider: TestMock,
        judge_provider: ExEval.JudgeProvider.TestMock,
        judge_provider_config: %{mock_response: "YES\nTest passes"},
        reporter: ExEval.Reporter.TestMock,
        reporter_opts: [test_pid: self()]
      }

      assert {:ok, results} = ExEval.run_by_category(["security"], opts)
      assert results.total == 1

      assert_receive {:eval_started, _}
      assert_receive {:eval_result, _}
      assert_receive {:eval_finished, _}
    end

    test "returns error when judge provider not provided and not in config" do
      original_judge_provider = Application.get_env(:ex_eval, :judge_provider)
      Application.delete_env(:ex_eval, :judge_provider)

      try do
        opts = %{
          provider: TestMock,
          evaluations: [:test_eval]
        }

        assert {:error, :judge_provider_required} = ExEval.run_evaluation(opts)
      after
        if original_judge_provider do
          Application.put_env(:ex_eval, :judge_provider, original_judge_provider)
        end
      end
    end
  end

  describe "Module provider integration tests" do
    test "list_evaluations/0 uses default Module provider" do
      evaluations = ExEval.list_evaluations()
      module_evaluations = Module.list_evaluations()

      assert evaluations == module_evaluations
      assert is_list(evaluations)
    end

    test "get_evaluation_info/1 works with Module provider" do
      result = ExEval.get_evaluation_info(TestEval)
      assert {:ok, info} = result
      assert info.module == TestEval
      assert info.case_count == 2
    end

    test "run_evaluation/1 works with Module provider and TestEval" do
      opts = %{
        evaluations: [TestEval],
        judge_provider: ExEval.JudgeProvider.TestMock,
        judge_provider_config: %{mock_response: "YES\nTest passes"},
        reporter: ExEval.Reporter.TestMock,
        reporter_opts: [test_pid: self()]
      }

      assert {:ok, results} = ExEval.run_evaluation(opts)
      assert results.total == 2

      assert_receive {:eval_started, _}
      assert_receive {:eval_result, _}
      assert_receive {:eval_result, _}
      assert_receive {:eval_finished, _}
    end
  end
end
