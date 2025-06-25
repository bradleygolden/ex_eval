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

  # Optional callbacks for providers that support editing
  @optional_callbacks [
    create_evaluation: 1,
    update_evaluation: 2,
    delete_evaluation: 1,
    create_case: 2,
    update_case: 3,
    delete_case: 2,
    import_cases: 3,
    export_cases: 2
  ]

  @doc """
  Create a new evaluation.

  Returns the created evaluation identifier.
  Only providers that support editing need to implement this.
  """
  @callback create_evaluation(evaluation_data :: map()) ::
              {:ok, evaluation_id :: any()} | {:error, term()}

  @doc """
  Update an existing evaluation.

  Returns the updated evaluation data.
  Only providers that support editing need to implement this.
  """
  @callback update_evaluation(evaluation_id :: any(), updates :: map()) ::
              {:ok, evaluation_data :: map()} | {:error, term()}

  @doc """
  Delete an evaluation.

  Returns :ok on success.
  Only providers that support editing need to implement this.
  """
  @callback delete_evaluation(evaluation_id :: any()) :: :ok | {:error, term()}

  @doc """
  Create a new case in an evaluation.

  Returns the created case identifier.
  Only providers that support editing need to implement this.
  """
  @callback create_case(evaluation_id :: any(), case_data :: map()) ::
              {:ok, case_id :: any()} | {:error, term()}

  @doc """
  Update an existing case in an evaluation.

  Returns the updated case data.
  Only providers that support editing need to implement this.
  """
  @callback update_case(evaluation_id :: any(), case_id :: any(), updates :: map()) ::
              {:ok, case_data :: map()} | {:error, term()}

  @doc """
  Delete a case from an evaluation.

  Returns :ok on success.
  Only providers that support editing need to implement this.
  """
  @callback delete_case(evaluation_id :: any(), case_id :: any()) :: :ok | {:error, term()}

  @doc """
  Import multiple cases into an evaluation from various formats.

  Supported formats include :csv, :json, :xlsx, etc.
  Returns the number of successfully imported cases.
  Only providers that support editing need to implement this.
  """
  @callback import_cases(evaluation_id :: any(), cases :: [map()], format :: atom()) ::
              {:ok, imported_count :: integer()} | {:error, term()}

  @doc """
  Export cases from an evaluation to various formats.

  Supported formats include :csv, :json, :xlsx, etc.
  Returns the exported cases in the requested format.
  Only providers that support editing need to implement this.
  """
  @callback export_cases(evaluation_id :: any(), format :: atom()) ::
              {:ok, cases :: [map()]} | {:error, term()}

  @doc """
  Get the capabilities of a dataset provider module.

  Returns a map indicating which optional operations the provider supports.

  ## Examples

      iex> ExEval.DatasetProvider.get_capabilities(ExEval.DatasetProvider.Module)
      %{
        read_only?: true,
        can_create_evaluations?: false,
        can_edit_evaluations?: false,
        can_delete_evaluations?: false,
        can_create_cases?: false,
        can_edit_cases?: false,
        can_delete_cases?: false,
        can_import?: false,
        can_export?: false
      }

  """
  def get_capabilities(provider_module) when is_atom(provider_module) do
    %{
      # All providers support reading
      read_only?: true,
      can_create_evaluations?: function_exported?(provider_module, :create_evaluation, 1),
      can_edit_evaluations?: function_exported?(provider_module, :update_evaluation, 2),
      can_delete_evaluations?: function_exported?(provider_module, :delete_evaluation, 1),
      can_create_cases?: function_exported?(provider_module, :create_case, 2),
      can_edit_cases?: function_exported?(provider_module, :update_case, 3),
      can_delete_cases?: function_exported?(provider_module, :delete_case, 2),
      can_import?: function_exported?(provider_module, :import_cases, 3),
      can_export?: function_exported?(provider_module, :export_cases, 2)
    }
  end

  @doc """
  Check if a provider supports editing operations (create, update, delete cases).

  Returns true if the provider implements all case editing callbacks.

  ## Examples

      iex> ExEval.DatasetProvider.supports_editing?(ExEval.DatasetProvider.Module)
      false

  """
  def supports_editing?(provider_module) when is_atom(provider_module) do
    function_exported?(provider_module, :create_case, 2) and
      function_exported?(provider_module, :update_case, 3) and
      function_exported?(provider_module, :delete_case, 2)
  end

  @doc """
  Check if a provider supports evaluation management (create, update, delete evaluations).

  Returns true if the provider implements all evaluation management callbacks.
  """
  def supports_evaluation_management?(provider_module) when is_atom(provider_module) do
    function_exported?(provider_module, :create_evaluation, 1) and
      function_exported?(provider_module, :update_evaluation, 2) and
      function_exported?(provider_module, :delete_evaluation, 1)
  end

  @doc """
  Check if a provider supports import/export operations.

  Returns true if the provider implements both import and export callbacks.
  """
  def supports_import_export?(provider_module) when is_atom(provider_module) do
    function_exported?(provider_module, :import_cases, 3) and
      function_exported?(provider_module, :export_cases, 2)
  end

  @doc """
  Check if a provider is read-only (supports no editing operations).

  Returns true if the provider implements none of the optional editing callbacks.
  """
  def read_only?(provider_module) when is_atom(provider_module) do
    not supports_editing?(provider_module) and
      not supports_evaluation_management?(provider_module) and
      not supports_import_export?(provider_module)
  end
end
