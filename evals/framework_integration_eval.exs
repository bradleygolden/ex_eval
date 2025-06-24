defmodule FrameworkIntegrationEval do
  @moduledoc """
  Integration test for the ExEval framework.

  This module tests the end-to-end functionality of ExEval using the mock judge provider
  to ensure the framework correctly:
  - Processes evaluation datasets
  - Calls response functions
  - Invokes the judge provider for judging
  - Reports results properly
  """

  use ExEval.Dataset,
    response_fn: &__MODULE__.test_response/1,
    judge_provider: ExEval.JudgeProvider.EvalMock,
    config: %{
      mock_response: "YES\nTest passes as expected"
    }

  def test_response(input) do
    case input do
      "simple_input" -> "simple output"
      "another_input" -> "another output"
      "multi_line_input" -> "line one\nline two\nline three"
      _ -> "default response"
    end
  end

  eval_dataset [
    %{
      input: "simple_input",
      judge_prompt: "Does the response exist?",
      category: "basic"
    },
    %{
      input: "another_input",
      judge_prompt: "Is this a valid response?",
      category: "basic"
    },
    %{
      input: "multi_line_input",
      judge_prompt: "Does the response contain multiple lines?",
      category: "advanced"
    }
  ]
end
