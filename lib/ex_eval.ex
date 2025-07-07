defmodule ExEval do
  @moduledoc """
  ExEval: Dataset-oriented evaluation framework for AI/LLM applications.

  This framework uses the LLM-as-judge pattern to evaluate AI responses
  against defined criteria, providing a clean, functional API similar to Req.

  ## Quick Start

      # Define your evaluation dataset
      dataset = [
        %{input: "What is 2+2?", judge_prompt: "Is the answer correct?", category: :math},
        %{input: "Tell me about safety", judge_prompt: "Is the response helpful?", category: :safety}
      ]
      
      # Define your AI response function
      response_fn = fn input ->
        case input do
          "What is 2+2?" -> "4"
          _ -> "I don't know"
        end
      end
      
      # Configure with custom judge
      config = 
        ExEval.new()
        |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
        |> ExEval.put_dataset(dataset)
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_experiment(:math_safety_eval)

      # Run evaluations asynchronously (default)
      {:ok, run_id} = ExEval.run(config)
      
      # Check status
      {:ok, state} = ExEval.Runner.get_run(run_id)
      
      # Run evaluations synchronously when needed
      results = ExEval.run(config, async: false)

  ## Creating Evaluations

  Define your evaluation dataset and response function inline:

      dataset = [
        %{
          input: "What is 2+2?",
          judge_prompt: "Is the mathematical answer correct?",
          category: :math
        }
      ]
      
      response_fn = fn input ->
        # Your AI response logic here
        MyAI.generate_response(input)
      end
  """

  defstruct judge: nil,
            reporter: ExEval.Reporter.Console,
            store: nil,
            max_concurrency: 10,
            timeout: 30_000,
            parallel: true,
            experiment: nil,
            params: %{},
            tags: %{},
            artifact_logging: false,
            dataset: nil,
            response_fn: nil,
            preprocessors: [],
            response_processors: [],
            postprocessors: [],
            middleware: []

  @type t :: %__MODULE__{
          judge: module() | {module(), keyword()} | nil,
          reporter: module() | {module(), keyword()},
          store: module() | {module(), keyword()} | nil,
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          parallel: boolean(),
          experiment: String.t() | atom() | nil,
          params: map(),
          tags: map(),
          artifact_logging: boolean(),
          dataset: list() | nil,
          response_fn: (any() -> any()) | nil,
          preprocessors: list(),
          response_processors: list(),
          postprocessors: list(),
          middleware: list()
        }

  @doc """
  Creates a new ExEval configuration with default settings.

  ## Examples

      # Create with defaults
      config = ExEval.new()
      
      # Create with options
      config = ExEval.new(
        judge: {ExEval.LangChain, model: "gpt-4"},
        reporter: {ExEval.Reporter.Console, colors: true},
        max_concurrency: 5
      )
  """
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Configures a consensus judge with multiple sub-judges.

  ## Options

  - `:strategy` - How to combine results: `:unanimous`, `:majority`, `:threshold` (default: `:majority`)
  - `:threshold` - For `:threshold` strategy, minimum agreement ratio (0.0-1.0)
  - `:aggregate_metadata` - Include all judge metadata (default: true)

  ## Examples

      # Majority consensus
      config = 
        ExEval.new()
        |> ExEval.put_consensus_judge([
          {MyJudge1, model: "gpt-4"},
          {MyJudge2, model: "claude-3"},
          MyJudge3
        ])

      # Unanimous consensus  
      config = 
        ExEval.new()
        |> ExEval.put_consensus_judge(
          [MyJudge1, MyJudge2],
          strategy: :unanimous
        )

      # 75% threshold
      config = 
        ExEval.new()
        |> ExEval.put_consensus_judge(
          [Judge1, Judge2, Judge3, Judge4],
          strategy: :threshold,
          threshold: 0.75
        )
  """
  def put_consensus_judge(%__MODULE__{} = config, judges, opts \\ []) when is_list(judges) do
    consensus_config = Keyword.merge([judges: judges], opts)
    put_judge(config, {ExEval.Judge.Composite.Consensus, consensus_config})
  end

  @doc """
  Configures a weighted voting judge with different weights for different judges.

  ## Examples

      # Weighted voting
      config = 
        ExEval.new()
        |> ExEval.put_weighted_judge([
          {{MyJudge1, model: "gpt-4"}, 0.5},
          {{MyJudge2, model: "claude-3"}, 0.3},
          {MyJudge3, 0.2}
        ])
  """
  def put_weighted_judge(%__MODULE__{} = config, weighted_judges, opts \\ [])
      when is_list(weighted_judges) do
    weighted_config = Keyword.merge([judges: weighted_judges], opts)
    put_judge(config, {ExEval.Judge.Composite.Weighted, weighted_config})
  end

  @doc """
  Sets the judge configuration.

  ## Examples

      # Module only (no configuration)
      config = 
        ExEval.new()
        |> ExEval.put_judge(MyApp.CustomJudge)
        
      # Module with configuration
      config =
        ExEval.new()
        |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4", temperature: 0.0)
        
      # Using tuple format
      config =
        ExEval.new()
        |> ExEval.put_judge({MyApp.CustomJudge, model: "gpt-4"})
  """
  def put_judge(%__MODULE__{} = config, {module, opts}) when is_atom(module) and is_list(opts) do
    %{config | judge: {module, opts}}
  end

  def put_judge(%__MODULE__{} = config, module) when is_atom(module) do
    %{config | judge: module}
  end

  def put_judge(%__MODULE__{} = config, module, opts) when is_atom(module) and is_list(opts) do
    %{config | judge: {module, opts}}
  end

  @doc """
  Sets the reporter configuration.

  ## Examples

      # Module only
      config =
        ExEval.new()
        |> ExEval.put_reporter(ExEval.Reporter.Console)
        
      # Module with configuration
      config =
        ExEval.new()
        |> ExEval.put_reporter(ExEval.Reporter.Console, trace: true)
        
      # Using tuple format  
      config =
        ExEval.new()
        |> ExEval.put_reporter({ExEval.Reporter.Console, trace: true})
  """
  def put_reporter(%__MODULE__{} = config, {module, opts})
      when is_atom(module) and is_list(opts) do
    %{config | reporter: {module, opts}}
  end

  def put_reporter(%__MODULE__{} = config, module) when is_atom(module) do
    %{config | reporter: module}
  end

  def put_reporter(%__MODULE__{} = config, module, opts) when is_atom(module) and is_list(opts) do
    %{config | reporter: {module, opts}}
  end

  @doc """
  Sets the maximum concurrency for parallel evaluation execution.
  """
  def put_max_concurrency(%__MODULE__{} = config, max_concurrency)
      when is_integer(max_concurrency) and max_concurrency > 0 do
    %{config | max_concurrency: max_concurrency}
  end

  @doc """
  Sets the timeout for individual evaluations in milliseconds.
  """
  def put_timeout(%__MODULE__{} = config, timeout) when is_integer(timeout) and timeout > 0 do
    %{config | timeout: timeout}
  end

  @doc """
  Enables or disables parallel execution.
  """
  def put_parallel(%__MODULE__{} = config, parallel) when is_boolean(parallel) do
    %{config | parallel: parallel}
  end

  @doc """
  Sets the experiment name for grouping related evaluation runs.

  Accepts both atoms and strings for experiment names.

  ## Examples

      # Using string
      config = ExEval.new()
      |> ExEval.put_experiment("gpt4_safety_v2")
      
      # Using atom  
      config = ExEval.new()
      |> ExEval.put_experiment(:safety_eval_2024)
  """
  def put_experiment(%__MODULE__{} = config, experiment)
      when is_atom(experiment) or is_binary(experiment) do
    %{config | experiment: experiment}
  end

  @doc """
  Sets parameters to track with this evaluation run.

  ## Examples

      config = ExEval.new()
      |> ExEval.put_params(%{
        model_version: "gpt-4-0613",
        temperature: 0.0,
        eval_dataset_version: "1.2.0"
      })
  """
  def put_params(%__MODULE__{} = config, params) when is_map(params) do
    %{config | params: Map.merge(config.params, params)}
  end

  @doc """
  Sets tags for categorizing and filtering evaluation runs.

  ## Examples

      config = ExEval.new()
      |> ExEval.put_tags(%{
        team: "safety",
        environment: "production",
        triggered_by: "github_action"
      })
  """
  def put_tags(%__MODULE__{} = config, tags) when is_map(tags) do
    %{config | tags: Map.merge(config.tags, tags)}
  end

  @doc """
  Enables or disables artifact logging for this run.

  ## Examples

      config = ExEval.new()
      |> ExEval.put_artifact_logging(true)
  """
  def put_artifact_logging(%__MODULE__{} = config, enabled) when is_boolean(enabled) do
    %{config | artifact_logging: enabled}
  end

  @doc """
  Sets the evaluation dataset inline instead of using a module.

  Allows defining evaluation cases directly without requiring a separate module.

  ## Examples

      dataset = [
        %{
          input: "What is 2+2?",
          judge_prompt: "Is the answer correct?",
          category: :math
        },
        %{
          input: "Tell me about safety",
          judge_prompt: "Is the response helpful and safe?",
          category: :safety
        }
      ]
      
      config = ExEval.new()
      |> ExEval.put_dataset(dataset)
  """
  def put_dataset(%__MODULE__{} = config, dataset) when is_list(dataset) do
    %{config | dataset: dataset}
  end

  @doc """
  Sets the response function that generates AI responses to evaluate.

  The function receives the input from each evaluation case and should return
  the response to be judged.

  ## Examples

      response_fn = fn input ->
        case input do
          "What is 2+2?" -> "4"
          "Tell me about safety" -> "Safety is important in AI systems..."
          _ -> "I don't know"
        end
      end
      
      config = ExEval.new()
      |> ExEval.put_response_fn(response_fn)
  """
  def put_response_fn(%__MODULE__{} = config, response_fn) when is_function(response_fn) do
    %{config | response_fn: response_fn}
  end

  @doc """
  Adds a preprocessor to transform inputs before response generation.

  Preprocessors are functions that receive input and return transformed input.
  They can also return {:error, reason} to halt processing.

  ## Examples

      # Add input sanitization
      config = ExEval.new()
      |> ExEval.put_preprocessor(&ExEval.Pipeline.Preprocessors.sanitize_input/1)

      # Add custom preprocessor
      config = ExEval.new()
      |> ExEval.put_preprocessor(fn input ->
        String.upcase(input)
      end)

      # Add module function reference
      config = ExEval.new()
      |> ExEval.put_preprocessor({MyModule, :my_function})
  """
  def put_preprocessor(%__MODULE__{} = config, processor) when is_function(processor) do
    %{config | preprocessors: config.preprocessors ++ [processor]}
  end

  def put_preprocessor(%__MODULE__{} = config, {module, function})
      when is_atom(module) and is_atom(function) do
    %{config | preprocessors: config.preprocessors ++ [{module, function}]}
  end

  def put_preprocessor(%__MODULE__{} = config, {module, function, args})
      when is_atom(module) and is_atom(function) and is_list(args) do
    %{config | preprocessors: config.preprocessors ++ [{module, function, args}]}
  end

  @doc """
  Adds a response processor to transform responses before judging.

  ## Examples

      # Strip markdown formatting
      config = ExEval.new()
      |> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.strip_markdown/1)

      # Validate response quality
      config = ExEval.new()
      |> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.validate_response/1)
  """
  def put_response_processor(%__MODULE__{} = config, processor) when is_function(processor) do
    %{config | response_processors: config.response_processors ++ [processor]}
  end

  def put_response_processor(%__MODULE__{} = config, {module, function})
      when is_atom(module) and is_atom(function) do
    %{config | response_processors: config.response_processors ++ [{module, function}]}
  end

  @doc """
  Adds a postprocessor to transform judge results after evaluation.

  ## Examples

      # Add confidence scoring
      config = ExEval.new()
      |> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.add_confidence_score/1)

      # Normalize to scores
      config = ExEval.new()
      |> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.normalize_to_score/1)
  """
  def put_postprocessor(%__MODULE__{} = config, processor) when is_function(processor) do
    %{config | postprocessors: config.postprocessors ++ [processor]}
  end

  def put_postprocessor(%__MODULE__{} = config, {module, function})
      when is_atom(module) and is_atom(function) do
    %{config | postprocessors: config.postprocessors ++ [{module, function}]}
  end

  @doc """
  Adds middleware to wrap the evaluation process.

  Middleware receives a next function and evaluation context.
  Use middleware for cross-cutting concerns like logging, retries, caching.

  ## Examples

      # Add timing logs
      config = ExEval.new()
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.timing_logger/2)

      # Add retry logic
      config = ExEval.new()
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.retry_on_failure/2)
  """
  def put_middleware(%__MODULE__{} = config, middleware) when is_function(middleware, 2) do
    %{config | middleware: config.middleware ++ [middleware]}
  end

  def put_middleware(%__MODULE__{} = config, {module, function})
      when is_atom(module) and is_atom(function) do
    %{config | middleware: config.middleware ++ [{module, function}]}
  end

  @doc """
  Sets the store configuration for persisting evaluation runs.

  ## Examples

      # Module only
      config =
        ExEval.new()
        |> ExEval.put_store(MyApp.PostgresStore)
        
      # Module with configuration
      config =
        ExEval.new()
        |> ExEval.put_store(MyApp.S3Store, bucket: "eval-results")
        
      # Using tuple format  
      config =
        ExEval.new()
        |> ExEval.put_store({MyApp.RedisStore, ttl: 3600})
  """
  def put_store(%__MODULE__{} = config, {module, opts})
      when is_atom(module) and is_list(opts) do
    %{config | store: {module, opts}}
  end

  def put_store(%__MODULE__{} = config, module) when is_atom(module) do
    %{config | store: module}
  end

  def put_store(%__MODULE__{} = config, module, opts) when is_atom(module) and is_list(opts) do
    %{config | store: {module, opts}}
  end

  @doc """
  Runs evaluations with the given configuration.

  ## Options

  - `:async` - When `true` (default), runs asynchronously and returns `{:ok, run_id}`. 
    When `false`, runs synchronously and returns results.
  - Other options are passed through to the runner.

  ## Examples

      # Define dataset and response function
      dataset = [
        %{input: "What is 2+2?", judge_prompt: "Is the answer correct?", category: :math},
        %{input: "Tell me about safety", judge_prompt: "Is the response helpful?", category: :safety}
      ]
      
      response_fn = fn
        "What is 2+2?" -> "4"
        _ -> "I don't know"
      end
      
      # Configure evaluation
      config = 
        ExEval.new()
        |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
        |> ExEval.put_dataset(dataset)
        |> ExEval.put_response_fn(response_fn)
        |> ExEval.put_experiment(:math_safety_eval)
        
      # Run asynchronously (default)
      {:ok, run_id} = ExEval.run(config)
      
      # Run synchronously when needed
      results = ExEval.run(config, async: false)
      
      # Monitor async progress
      {:ok, state} = ExEval.Runner.get_run(run_id)
  """
  def run(%__MODULE__{} = config, opts \\ []) do
    case Keyword.get(opts, :async, true) do
      true ->
        # Remove :async from opts before passing to runner
        runner_opts = Keyword.delete(opts, :async)
        ExEval.Runner.run(config, runner_opts)

      false ->
        # Remove :async from opts before passing to runner
        runner_opts = Keyword.delete(opts, :async)
        ExEval.Runner.run_sync(config, runner_opts)
    end
  end
end
