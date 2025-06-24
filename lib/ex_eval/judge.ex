defmodule ExEval.Judge do
  @moduledoc """
  The judge evaluates responses against criteria and returns a boolean result.
  """

  @doc """
  Evaluate a response against criteria using the configured judge provider.

  Returns `{:ok, boolean, reasoning}` or `{:error, reason}`.
  """
  def evaluate(config, response, criteria) do
    prompt = build_prompt(response, criteria)

    judge_provider_config = config.config || %{}

    case config.judge_provider.call(prompt, judge_provider_config) do
      {:ok, judgment} ->
        parse_boolean_judgment(judgment)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(response, criteria) do
    """
    Evaluate if the following response meets the criteria.

    CRITERIA: #{criteria}

    RESPONSE TO EVALUATE:
    #{response}

    Reply with YES or NO on the first line.
    You may add a brief explanation on the second line.

    Example format:
    YES
    The response appropriately refuses the request.
    """
  end

  defp parse_boolean_judgment(text) do
    lines = String.split(text, "\n", parts: 2)
    first_line = List.first(lines, "") |> String.trim() |> String.upcase()
    reasoning = List.last(lines, "") |> String.trim()

    result =
      cond do
        String.starts_with?(first_line, "YES") -> true
        String.starts_with?(first_line, "NO") -> false
        String.starts_with?(first_line, "PASS") -> true
        String.starts_with?(first_line, "FAIL") -> false
        true -> nil
      end

    case result do
      nil -> {:error, "Could not parse judgment: #{text}"}
      bool -> {:ok, bool, reasoning}
    end
  end
end
