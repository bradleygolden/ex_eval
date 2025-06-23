defmodule ExEval.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing ExEval without making real LLM calls.

  ## Usage

      # Configure to always pass
      ExEval.new(
        adapter: ExEval.Adapters.Mock,
        config: %{mock_response: "YES\\nThe response meets all criteria"}
      )
      
      # Configure to always fail
      ExEval.new(
        adapter: ExEval.Adapters.Mock,
        config: %{mock_response: "NO\\nThe response does not meet criteria"}
      )
      
      # Use a function for dynamic responses
      ExEval.new(
        adapter: ExEval.Adapters.Mock,
        config: %{
          mock_response: fn prompt ->
            if String.contains?(prompt, "security") do
              {:ok, "YES\\nSecurity check passed"}
            else
              {:ok, "NO\\nNot a security-related prompt"}
            end
          end
        }
      )
  """

  @behaviour ExEval.Adapter

  @impl true
  def call(prompt, config) do
    case config[:mock_response] do
      nil ->
        {:ok, "YES\nMock evaluation passed"}

      {:ok, true} ->
        {:ok, "YES\nMock evaluation passed"}

      {:ok, false} ->
        {:ok, "NO\nMock evaluation failed"}

      response when is_binary(response) ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}

      fun when is_function(fun, 1) ->
        fun.(prompt)
    end
  end
end
