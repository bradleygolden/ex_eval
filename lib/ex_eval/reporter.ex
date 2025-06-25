defmodule ExEval.Reporter do
  @moduledoc """
  Behaviour for evaluation result reporters.

  Reporters handle the presentation and storage of evaluation results.
  Implement this behaviour to create custom output formats like JSON files,
  database storage, web dashboards, or console output.
  """

  @typedoc """
  Reporter configuration options.
  """
  @type config :: map()

  @typedoc """
  A single evaluation result.
  """
  @type result :: %{
          required(:status) => :passed | :failed | :error,
          required(:input) => any(),
          required(:judge_prompt) => String.t(),
          optional(:reasoning) => String.t(),
          optional(:response) => String.t(),
          optional(:error) => String.t(),
          optional(:category) => atom() | String.t(),
          optional(:module) => module(),
          optional(:duration_ms) => non_neg_integer(),
          optional(:dataset) => map()
        }

  @typedoc """
  The runner state containing all evaluation information.
  """
  @type runner :: %ExEval.Runner{
          id: String.t(),
          datasets: list(),
          options: keyword(),
          metadata: map(),
          results: list(result()),
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }

  @doc """
  Called before evaluations begin.

  Use this to print headers, initialize files, open database connections, etc.
  """
  @callback init(runner(), config()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Called after each evaluation completes.

  Use this to print progress, stream results to a file, or update a UI.
  The state returned will be passed to the next call.
  """
  @callback report_result(result(), state :: any(), config()) ::
              {:ok, new_state :: any()} | {:error, reason :: any()}

  @doc """
  Called after all evaluations complete.

  Use this to print summaries, close files, finalize reports, etc.
  """
  @callback finalize(runner(), state :: any(), config()) :: :ok | {:error, reason :: any()}
end
