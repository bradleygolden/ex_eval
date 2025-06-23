defmodule ExEvalTest do
  use ExUnit.Case

  describe "new/1" do
    test "creates evaluator with adapter and config" do
      evaluator =
        ExEval.new(adapter: ExEval.Adapters.Mock, config: %{mock_response: "YES\nTest passed"})

      assert %ExEval{} = evaluator
      assert evaluator.adapter == ExEval.Adapters.Mock
      assert evaluator.config == %{mock_response: "YES\nTest passed"}
    end

    test "requires adapter" do
      assert_raise KeyError, fn ->
        ExEval.new(config: %{})
      end
    end

    test "defaults config to empty map" do
      evaluator = ExEval.new(adapter: ExEval.Adapters.Mock)
      assert evaluator.config == %{}
    end
  end
end
