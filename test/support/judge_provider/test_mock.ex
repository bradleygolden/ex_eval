defmodule ExEval.JudgeProvider.TestMock do
  @moduledoc """
  Mock judge provider that sends messages to the test process instead of making LLM calls.

  This judge provider allows tests to capture and control LLM interactions by receiving 
  messages and returning configurable responses.
  """

  @behaviour ExEval.JudgeProvider

  @impl ExEval.JudgeProvider
  def call(prompt, config) do
    test_pid = Map.get(config, :test_pid, self())
    response = Map.get(config, :mock_response, "YES\nTest response")

    # Send the prompt to the test process for verification
    send(test_pid, {:llm_call, %{prompt: prompt, config: config}})

    # Return the configured response (handle both success and error cases)
    case response do
      {:error, reason} -> {:error, reason}
      success_response -> {:ok, success_response}
    end
  end
end
