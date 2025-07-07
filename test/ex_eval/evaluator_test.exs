defmodule ExEval.EvaluatorTest do
  use ExUnit.Case

  # Test judge that returns configurable results
  defmodule TestJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(response, criteria, config) do
      case config[:mode] do
        :pass -> {:ok, true, %{reasoning: "Response meets criteria: #{criteria}"}}
        :fail -> {:ok, false, %{reasoning: "Response does not meet criteria"}}
        :error -> {:error, "Judge error: #{config[:error_message] || "unknown"}"}
        :check_args -> {:ok, true, %{reasoning: "Response: #{response}, Criteria: #{criteria}"}}
        _ -> {:ok, true, %{reasoning: "Default pass"}}
      end
    end
  end

  describe "evaluate/3 with module format" do
    test "calls judge module with empty config" do
      result = ExEval.Evaluator.evaluate(TestJudge, "test response", "test criteria")
      assert {:ok, true, %{reasoning: "Default pass"}} = result
    end

    test "passes response and criteria to judge" do
      result =
        ExEval.Evaluator.evaluate(
          {TestJudge, mode: :check_args},
          "my response",
          "my criteria"
        )

      assert {:ok, true, %{reasoning: "Response: my response, Criteria: my criteria"}} = result
    end
  end

  describe "evaluate/3 with {module, config} tuple format" do
    test "passes config as keyword list" do
      result =
        ExEval.Evaluator.evaluate(
          {TestJudge, mode: :pass},
          "response",
          "criteria"
        )

      assert {:ok, true, %{reasoning: "Response meets criteria: criteria"}} = result
    end

    test "handles failing judge result" do
      result =
        ExEval.Evaluator.evaluate(
          {TestJudge, mode: :fail},
          "response",
          "criteria"
        )

      assert {:ok, false, %{reasoning: "Response does not meet criteria"}} = result
    end

    test "handles judge error" do
      result =
        ExEval.Evaluator.evaluate(
          {TestJudge, mode: :error, error_message: "API failure"},
          "response",
          "criteria"
        )

      assert {:error, "Judge error: API failure"} = result
    end

    test "converts keyword list config to map" do
      # The evaluator should convert the keyword list to a map before passing to judge
      result =
        ExEval.Evaluator.evaluate(
          {TestJudge, [mode: :pass, extra: "data"]},
          "response",
          "criteria"
        )

      assert {:ok, true, _} = result
    end
  end

  describe "evaluate/3 with ExEval struct" do
    test "extracts judge from ExEval struct" do
      config = ExEval.new() |> ExEval.put_judge(TestJudge)

      result = ExEval.Evaluator.evaluate(config, "response", "criteria")
      assert {:ok, true, %{reasoning: "Default pass"}} = result
    end

    test "handles ExEval struct with configured judge" do
      config = ExEval.new() |> ExEval.put_judge(TestJudge, mode: :pass)

      result = ExEval.Evaluator.evaluate(config, "response", "criteria")
      assert {:ok, true, %{reasoning: "Response meets criteria: criteria"}} = result
    end
  end
end
