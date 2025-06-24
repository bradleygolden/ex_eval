defmodule ExEval.DatasetProvider do
  @moduledoc """
  Behaviour for dataset providers that load evaluation cases from various sources.

  Providers must implement `load/1` which returns a dataset map containing:
  - `:cases` - Enumerable of evaluation cases
  - `:response_fn` - Function that generates responses to evaluate
  - `:judge_provider` - Optional judge provider module for the LLM judge
  - `:config` - Optional configuration for the judge provider
  - `:setup_fn` - Optional setup function to run before evaluation
  - `:metadata` - Optional metadata about the dataset
  """

  @typedoc """
  An evaluation case with input and judge prompt.
  """
  @type eval_case :: %{
          required(:input) => any(),
          required(:judge_prompt) => String.t(),
          optional(:category) => atom() | String.t(),
          optional(any()) => any()
        }

  @typedoc """
  A dataset containing evaluation cases and configuration.
  """
  @type dataset :: %{
          required(:cases) => Enumerable.t(eval_case()),
          required(:response_fn) => function(),
          optional(:judge_provider) => module(),
          optional(:config) => map(),
          optional(:setup_fn) => (-> any()),
          optional(:metadata) => map()
        }

  @doc """
  Load a dataset with the given options.

  Returns a map containing evaluation cases and configuration.
  """
  @callback load(opts :: keyword()) :: dataset()

  @doc """
  List all available evaluations from this provider.

  Returns a list of evaluation identifiers. For module-based providers,
  this might be module names. For database providers, this might be
  dataset names or IDs.
  """
  @callback list_evaluations(opts :: keyword()) :: [any()]

  @doc """
  Get detailed information about a specific evaluation.

  Returns metadata about the evaluation including categories,
  case count, and other relevant information.
  """
  @callback get_evaluation_info(evaluation_id :: any(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Get all unique categories available from this provider.

  Returns a list of category names across all evaluations.
  """
  @callback get_categories(opts :: keyword()) :: [String.t()]

  @doc """
  Get evaluations filtered by categories.

  Returns a list of evaluation identifiers that contain
  cases in the specified categories.
  """
  @callback list_evaluations_by_category(categories :: [String.t()], opts :: keyword()) :: [any()]
end
