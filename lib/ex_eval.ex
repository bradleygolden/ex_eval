defmodule ExEval do
  @moduledoc """
  ExEval: Dataset-oriented evaluation framework for AI/LLM applications.

  This framework uses the LLM-as-judge pattern to evaluate AI responses
  against defined criteria, with support for async execution and real-time monitoring.

  ## Quick Start

      # Run evaluations synchronously (CLI/tests)
      results = ExEval.Runner.run_sync([MyEval, OtherEval])
      
      # Run evaluations asynchronously (LiveView)
      {:ok, run_id} = ExEval.Runner.run([MyEval, OtherEval])
      
      # Get run status
      {:ok, state} = ExEval.Runner.get_run(run_id)

  ## Creating Evaluations

      defmodule MyEval do
        use ExEval.DatasetProvider.Module

        def response_fn(input) do
          # Your AI response logic here
        end

        eval_dataset [
          %{
            input: "Test input",
            judge_prompt: "Does the response make sense?"
          }
        ]
      end
  """

  defstruct [:judge_provider, :config]

  @type t :: %__MODULE__{
          judge_provider: module(),
          config: map()
        }

  @doc """
  Creates a new ExEval configuration for judge providers.
  """
  def new(opts) do
    %__MODULE__{
      judge_provider: Keyword.fetch!(opts, :judge_provider),
      config: Keyword.get(opts, :config, %{})
    }
  end

  @doc """
  Simple helper to run evaluations with basic options.

  For more control, use ExEval.Runner.run_sync/2 directly.
  """
  def run(datasets, opts \\ []) do
    ExEval.Runner.run_sync(datasets, opts)
  end

  @doc """
  Async helper to start evaluations and return run ID.

  For more control, use ExEval.Runner.run/2 directly.
  """
  def run_async(datasets, opts \\ []) do
    ExEval.Runner.run(datasets, opts)
  end
end
