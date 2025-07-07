defmodule ExEval.Evaluator do
  @moduledoc """
  The evaluator orchestrates response evaluation against criteria using configured LLM judges.

  The evaluator delegates prompt building and response parsing to the judge providers,
  allowing each provider to optimize for their specific LLM's capabilities.

  Supports both module-only and {module, config} formats for judge configuration.
  """

  @doc """
  Evaluate a response against criteria using the configured judge provider.

  Returns `{:ok, boolean, reasoning}` or `{:error, reason}`.
  """
  def evaluate(%ExEval{judge: judge}, response, criteria) when not is_nil(judge) do
    evaluate(judge, response, criteria)
  end

  # Handle module-only format
  def evaluate(module, response, criteria) when is_atom(module) do
    if function_exported?(module, :call, 3) do
      module.call(response, criteria, %{})
    else
      {:error, "Judge module #{inspect(module)} does not implement call/3"}
    end
  end

  # Handle {module, config} tuple format
  def evaluate({module, config}, response, criteria) when is_atom(module) do
    if function_exported?(module, :call, 3) do
      config_map = Enum.into(config, %{})
      module.call(response, criteria, config_map)
    else
      {:error, "Judge module #{inspect(module)} does not implement call/3"}
    end
  end

  # Handle invalid judge configuration
  def evaluate(judge_config, _response, _criteria) do
    {:error, "Invalid judge configuration: #{inspect(judge_config)}"}
  end
end
