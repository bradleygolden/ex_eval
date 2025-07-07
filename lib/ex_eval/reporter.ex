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
          required(:status) => :evaluated | :error,
          required(:input) => any(),
          required(:judge_prompt) => String.t(),
          optional(:result) => any(),
          optional(:metadata) => map(),
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

  @doc """
  List all available reporters.

  Returns a list of reporter modules that are currently loaded and available.

  ## Examples

      iex> ExEval.Reporter.available_reporters()
      [ExEval.Reporter.Console]

  """
  def available_reporters do
    [ExEval.Reporter.Console]
  end

  @doc """
  Get information about a reporter's requirements.

  Returns a map with information about what the reporter needs to function.

  ## Examples

      iex> ExEval.Reporter.reporter_info(ExEval.Reporter.Console)
      %{
        name: "Console",
        description: "Outputs results to the console",
        required_deps: [],
        required_config: []
      }

  """
  def reporter_info(reporter_module) when is_atom(reporter_module) do
    case reporter_module do
      ExEval.Reporter.Console ->
        %{
          name: "Console",
          description: "Outputs evaluation results to the console with colored output",
          required_deps: [],
          required_config: [],
          optional_config: [:trace]
        }

      _ ->
        %{
          name: inspect(reporter_module),
          description: "Custom reporter",
          required_deps: :unknown,
          required_config: :unknown
        }
    end
  end
end
