defmodule ExEval.DatasetProvider do
  @moduledoc """
  Behaviour for dataset providers that load evaluation cases from various sources.

  Providers must implement `load/1` which returns a dataset map containing:
  - `:cases` - Enumerable of evaluation cases
  - `:response_fn` - Function that generates responses to evaluate
  - `:adapter` - Optional adapter module for the LLM judge
  - `:config` - Optional configuration for the adapter
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
          optional(:adapter) => module(),
          optional(:config) => map(),
          optional(:setup_fn) => (-> any()),
          optional(:metadata) => map()
        }

  @doc """
  Load a dataset with the given options.

  Returns a map containing evaluation cases and configuration.
  """
  @callback load(opts :: keyword()) :: dataset()
end
