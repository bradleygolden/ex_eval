defmodule ExEval do
  @moduledoc """
  ExEval - Dataset-oriented evaluation framework for AI/LLM applications.

  ExEval provides a simple way to evaluate AI responses using semantic criteria
  rather than exact matches. It's designed to be similar to ExUnit but specifically
  for testing AI behavior using the LLM-as-judge pattern.
  """

  defstruct [:adapter, :config]

  @doc """
  Creates a new ExEval instance with the given options.

  ## Options

    * `:adapter` - The adapter module to use for LLM judgments (required)
    * `:config` - Configuration options to pass to the adapter (optional)

  ## Examples

      iex> ExEval.new(adapter: ExEval.Adapters.LangChain)
      %ExEval{adapter: ExEval.Adapters.LangChain, config: %{}}
      
      iex> ExEval.new(adapter: ExEval.Adapters.LangChain, config: %{model: "gpt-4"})
      %ExEval{adapter: ExEval.Adapters.LangChain, config: %{model: "gpt-4"}}
  """
  def new(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    config = Keyword.get(opts, :config, %{})

    %__MODULE__{
      adapter: adapter,
      config: config
    }
  end
end
