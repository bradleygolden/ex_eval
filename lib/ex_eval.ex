defmodule ExEval do
  @moduledoc """
  ExEval - Dataset-oriented evaluation framework for AI/LLM applications.

  ExEval provides a simple way to evaluate AI responses using semantic criteria
  rather than exact matches. It's designed to be similar to ExUnit but specifically
  for testing AI behavior using the LLM-as-judge pattern.
  """

  defstruct [:judge_provider, :config]

  @doc """
  Creates a new ExEval instance with the given options.

  ## Options

    * `:judge_provider` - The adapter module to use for LLM judgments (required)
    * `:config` - Configuration options to pass to the judge provider (optional)

  ## Examples

      iex> ExEval.new(judge_provider: ExEval.JudgeProvider.LangChain)
      %ExEval{judge_provider: ExEval.JudgeProvider.LangChain, config: %{}}
      
      iex> ExEval.new(judge_provider: ExEval.JudgeProvider.LangChain, config: %{model: "gpt-4.1-mini"})
      %ExEval{judge_provider: ExEval.JudgeProvider.LangChain, config: %{model: "gpt-4.1-mini"}}
  """
  def new(opts) do
    judge_provider = Keyword.fetch!(opts, :judge_provider)
    config = Keyword.get(opts, :config, %{})

    %__MODULE__{
      judge_provider: judge_provider,
      config: config
    }
  end

  # Provider-based API functions for GUI and programmatic access

  alias ExEval.Runner

  @default_provider ExEval.DatasetProvider.Module

  @doc """
  Lists all available evaluations using the specified provider.

  ## Examples

      # Use default provider (Module)
      iex> ExEval.list_evaluations()
      [MyApp.CustomerSupportEval, MyApp.SecurityEval]
      
      # Use specific provider  
      iex> ExEval.list_evaluations(ExEval.DatasetProvider.Database)
      ["security_suite", "helpfulness_suite"]
      
      # Use provider with options
      iex> ExEval.list_evaluations(ExEval.DatasetProvider.Module, path: "custom/**/*.exs")
      [CustomEval]
  """
  def list_evaluations(provider \\ @default_provider, opts \\ [])
  def list_evaluations(opts, []) when is_list(opts), do: list_evaluations(@default_provider, opts)
  def list_evaluations(provider, opts), do: provider.list_evaluations(opts)

  @doc """
  Gets detailed information about an evaluation.

  Returns metadata including categories, test case count, and descriptions.

  ## Examples

      # Module provider
      iex> ExEval.get_evaluation_info(MyApp.CustomerSupportEval)
      {:ok, %{
        module: MyApp.CustomerSupportEval,
        categories: ["security", "helpfulness"],
        case_count: 15,
        cases: [...]
      }}
      
      # Database provider  
      iex> ExEval.get_evaluation_info("security_suite", ExEval.DatasetProvider.Database)
      {:ok, %{
        id: "security_suite",
        categories: ["security"],
        case_count: 25
      }}
  """
  def get_evaluation_info(evaluation_id, provider \\ @default_provider, opts \\ [])

  def get_evaluation_info(evaluation_id, opts, []) when is_list(opts),
    do: get_evaluation_info(evaluation_id, @default_provider, opts)

  def get_evaluation_info(evaluation_id, provider, opts),
    do: provider.get_evaluation_info(evaluation_id, opts)

  @doc """
  Gets all unique categories across evaluations.

  ## Examples

      iex> ExEval.get_categories()
      ["security", "helpfulness", "accuracy", "compliance"]
      
      iex> ExEval.get_categories(ExEval.DatasetProvider.Database)
      ["security", "compliance"]
  """
  def get_categories(provider \\ @default_provider, opts \\ [])
  def get_categories(opts, []) when is_list(opts), do: get_categories(@default_provider, opts)
  def get_categories(provider, opts), do: provider.get_categories(opts)

  @doc """
  Gets evaluations filtered by categories.

  ## Examples

      iex> ExEval.list_evaluations_by_category(["security"])
      [MyApp.SecurityEval]
      
      iex> ExEval.list_evaluations_by_category(["security"], ExEval.DatasetProvider.Database)
      ["security_suite", "auth_suite"]
  """
  def list_evaluations_by_category(categories, provider \\ @default_provider, opts \\ [])

  def list_evaluations_by_category(categories, opts, []) when is_list(opts),
    do: list_evaluations_by_category(categories, @default_provider, opts)

  def list_evaluations_by_category(categories, provider, opts),
    do: provider.list_evaluations_by_category(categories, opts)

  @doc """
  Runs evaluations with the given options.

  This function supports runtime configuration and returns structured results
  suitable for GUI consumption.

  ## Options

    * `:evaluations` - List of evaluation IDs to run (default: all)
    * `:categories` - List of categories to filter by
    * `:judge_provider` - Adapter to use for LLM calls
    * `:judge_provider_config` - Configuration for the adapter
    * `:max_concurrency` - Maximum concurrent evaluations
    * `:sequential` - Run sequentially instead of parallel
    * `:provider` - Dataset provider to use (default: Module)
    * `:reporter` - Reporter module to use (default: no output)

  ## Examples

      iex> ExEval.run_evaluation(%{
      ...>   evaluations: [MyApp.CustomerSupportEval],
      ...>   judge_provider: ExEval.JudgeProvider.LangChain,
      ...>   judge_provider_config: %{model: "gpt-4.1-mini", temperature: 0.1}
      ...> })
      {:ok, %{
        total: 10,
        passed: 8,
        failed: 2,
        errors: 0,
        results: [...]
      }}
  """
  def run_evaluation(opts \\ %{}) do
    with {:ok, config} <- validate_run_config(opts),
         {:ok, evaluations} <- resolve_evaluations(config),
         {:ok, filtered_evaluations} <- filter_by_categories(evaluations, config) do
      # Create runtime ExEval configuration
      ex_eval_config = %ExEval{
        judge_provider: config[:judge_provider],
        config: config[:judge_provider_config] || %{}
      }

      # Convert evaluation IDs to datasets using the provider
      provider = Map.get(config, :provider, @default_provider)
      datasets = Enum.map(filtered_evaluations, &provider.load(module: &1))

      # Run the evaluations
      runner_opts = [
        max_concurrency: config[:max_concurrency] || 5,
        sequential: config[:sequential] || false,
        judge_provider: ex_eval_config.judge_provider,
        judge_provider_config: ex_eval_config.config
      ]

      # Add reporter and reporter config if provided
      runner_opts =
        case config[:reporter] do
          nil ->
            runner_opts

          reporter ->
            opts_with_reporter = Keyword.put(runner_opts, :reporter, reporter)

            case config[:reporter_opts] do
              nil -> opts_with_reporter
              reporter_opts -> Keyword.put(opts_with_reporter, :reporter_config, reporter_opts)
            end
        end

      runner_result = Runner.run(datasets, runner_opts)
      {:ok, format_results(runner_result.results)}
    end
  end

  @doc """
  Runs a single evaluation with the given configuration.

  ## Examples

      iex> ExEval.run_single_evaluation(MyApp.CustomerSupportEval, %{
      ...>   judge_provider: ExEval.JudgeProvider.LangChain,
      ...>   judge_provider_config: %{model: "gpt-4.1-mini"}
      ...> })
      {:ok, %{passed: 8, failed: 2, results: [...]}}
  """
  def run_single_evaluation(evaluation_id, opts \\ %{}) do
    run_evaluation(Map.put(opts, :evaluations, [evaluation_id]))
  end

  @doc """
  Runs evaluations for specific categories.

  ## Examples

      iex> ExEval.run_by_category(["security", "compliance"], %{
      ...>   judge_provider: ExEval.JudgeProvider.LangChain
      ...> })
      {:ok, %{total: 25, passed: 20, failed: 5, results: [...]}}
  """
  def run_by_category(categories, opts \\ %{}) when is_list(categories) do
    run_evaluation(Map.put(opts, :categories, categories))
  end

  # Private functions

  defp validate_run_config(opts) do
    # Basic validation - ensure judge provider is provided
    case Map.get(opts, :judge_provider) do
      nil ->
        # Try to get from application config
        case Application.get_env(:ex_eval, :judge_provider) do
          nil -> {:error, :judge_provider_required}
          adapter -> {:ok, Map.put(opts, :judge_provider, adapter)}
        end

      _ ->
        {:ok, opts}
    end
  end

  defp resolve_evaluations(%{evaluations: evaluations}) when is_list(evaluations),
    do: {:ok, evaluations}

  defp resolve_evaluations(%{provider: provider} = config) do
    opts = Map.get(config, :provider_opts, [])
    {:ok, provider.list_evaluations(opts)}
  end

  defp resolve_evaluations(_), do: {:ok, list_evaluations()}

  defp filter_by_categories(evaluations, %{categories: categories, provider: provider} = config)
       when is_list(categories) do
    opts = Map.get(config, :provider_opts, [])
    filtered = provider.list_evaluations_by_category(categories, opts)
    {:ok, Enum.filter(evaluations, &(&1 in filtered))}
  end

  defp filter_by_categories(evaluations, %{categories: categories}) when is_list(categories) do
    filtered = list_evaluations_by_category(categories)
    {:ok, Enum.filter(evaluations, &(&1 in filtered))}
  end

  defp filter_by_categories(evaluations, _), do: {:ok, evaluations}

  defp format_results(results) do
    total = length(results)

    passed =
      Enum.count(results, fn result ->
        Map.get(result, :judgment) == :pass or Map.get(result, :status) == :pass
      end)

    failed =
      Enum.count(results, fn result ->
        Map.get(result, :judgment) == :fail or Map.get(result, :status) == :fail
      end)

    errors =
      Enum.count(results, fn result ->
        Map.get(result, :judgment) == :error or Map.get(result, :status) == :error
      end)

    %{
      total: total,
      passed: passed,
      failed: failed,
      errors: errors,
      results: results
    }
  end
end
