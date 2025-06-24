defmodule ExEval.JudgeTest do
  use ExUnit.Case

  describe "evaluate/3" do
    test "returns {:ok, true, reasoning} for YES response" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "YES\nThe response is correct"}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check if correct")

      assert {:ok, true, "The response is correct"} = result
    end

    test "returns {:ok, false, reasoning} for NO response" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "NO\nThe response is incorrect"}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check if correct")

      assert {:ok, false, "The response is incorrect"} = result
    end

    test "handles PASS/FAIL responses" do
      config_pass = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "PASS\nLooks good"}
      }

      config_fail = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "FAIL\nNot good"}
      }

      assert {:ok, true, "Looks good"} =
               ExEval.Judge.evaluate(config_pass, "response", "criteria")

      assert {:ok, false, "Not good"} = ExEval.Judge.evaluate(config_fail, "response", "criteria")
    end

    test "handles responses without reasoning" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "YES"}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check")

      assert {:ok, true, "YES"} = result
    end

    test "returns error for invalid response format" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "MAYBE\nNot sure"}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check")

      assert {:error, "Could not parse judgment: MAYBE\nNot sure"} = result
    end

    test "passes through judge provider errors" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: {:error, "API error"}}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check")

      assert {:error, "API error"} = result
    end

    test "handles case insensitive responses" do
      config = %ExEval{
        judge_provider: ExEval.JudgeProvider.TestMock,
        config: %{mock_response: "yes\nAll good"}
      }

      result = ExEval.Judge.evaluate(config, "test response", "check")

      assert {:ok, true, "All good"} = result
    end
  end
end
