defmodule ExEval.JudgeTest do
  use ExUnit.Case

  # Inline test judge mock
  defmodule TestJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, config) do
      case config[:mock_result] do
        nil -> {:ok, true, %{reasoning: "Test response"}}
        true -> {:ok, true, %{reasoning: "Test response passed"}}
        false -> {:ok, false, %{reasoning: "Test response failed"}}
        result -> result
      end
    end
  end

  describe "evaluate/3" do
    test "returns {:ok, true, reasoning} for structured result" do
      judge = {TestJudge, mock_result: {:ok, true, %{reasoning: "The response is correct"}}}

      result = ExEval.Evaluator.evaluate(judge, "test response", "check if correct")

      assert {:ok, true, %{reasoning: "The response is correct"}} = result
    end

    test "returns {:ok, false, reasoning} for structured result" do
      judge = {TestJudge, mock_result: {:ok, false, %{reasoning: "The response is incorrect"}}}

      result = ExEval.Evaluator.evaluate(judge, "test response", "check if correct")

      assert {:ok, false, %{reasoning: "The response is incorrect"}} = result
    end

    test "handles boolean shortcuts" do
      judge_pass = {TestJudge, mock_result: true}
      judge_fail = {TestJudge, mock_result: false}

      assert {:ok, true, %{reasoning: "Test response passed"}} =
               ExEval.Evaluator.evaluate(judge_pass, "response", "criteria")

      assert {:ok, false, %{reasoning: "Test response failed"}} =
               ExEval.Evaluator.evaluate(judge_fail, "response", "criteria")
    end

    test "handles default case when no mock_result provided" do
      judge = TestJudge

      result = ExEval.Evaluator.evaluate(judge, "test response", "check")

      assert {:ok, true, %{reasoning: "Test response"}} = result
    end

    test "passes through judge provider errors" do
      judge = {TestJudge, mock_result: {:error, "API error"}}

      result = ExEval.Evaluator.evaluate(judge, "test response", "check")

      assert {:error, "API error"} = result
    end
  end
end
