# ExEval

**The core evaluation framework for AI/LLM applications in Elixir.**

ExEval provides a structured way to test AI responses using the LLM-as-judge pattern. Instead of exact string matching, you define evaluation criteria in natural language and let an LLM judge whether responses meet those criteria.

## Core Features

- **Inline Configuration**: Define datasets and response functions directly in code
- **Async-First Execution**: Supervised processes with real-time status updates (configurable sync/async)  
- **Flexible Judge Results**: Support for boolean, numeric, categorical, and multi-dimensional results
- **Composite Judges**: Consensus and weighted voting patterns for complex evaluations
- **Pipeline Processors**: Transform inputs, responses, and results at any stage
- **Pluggable Architecture**: Custom judges, reporters, and stores via behaviors
- **Experiment Tracking**: MLflow-style metadata, parameters, and tags

## Installation

Add ExEval to your dependencies:

```elixir
def deps do
  [
    {:ex_eval, github: "bradleygolden/ex_eval", branch: "main"}
  ]
end
```

## Quick Start

```elixir
# Define your evaluation dataset
dataset = [
  %{
    input: "What is 2+2?",
    judge_prompt: "Is the mathematical answer correct?",
    category: :math
  }
]

# Define your AI response function
response_fn = fn input ->
  case input do
    "What is 2+2?" -> "2 + 2 = 4"
    _ -> "I don't know"
  end
end

# Configure and run evaluation with custom judge
# Run asynchronously (default)
{:ok, run_id} = 
  ExEval.new()
  |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_experiment(:math_eval)
  |> ExEval.run()

# Check status
{:ok, state} = ExEval.Runner.get_run(run_id)

# Or run synchronously
results = 
  ExEval.new()
  |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_experiment(:math_eval)
  |> ExEval.run(async: false)

# Handle results
if results.status == :completed do
  IO.inspect(results.metrics)
else
  IO.puts("Evaluation failed: #{results.error}")
end
```

## LangChain Integration

ExEval includes a LangChain integration that provides judge implementations for LLM providers. This integration supports multiple providers, evaluation modes, and features like JSON schema validation.

### Installation

Add the LangChain extension to your dependencies:

```elixir
def deps do
  [
    {:ex_eval, github: "bradleygolden/ex_eval", branch: "main"},
    {:ex_eval_langchain, github: "bradleygolden/ex_eval_langchain", branch: "main"}
  ]
end
```

### Quick Example

```elixir
# Set your API key
# export OPENAI_API_KEY="your-key-here"

dataset = [
  %{
    input: "What is 2+2?",
    judge_prompt: "Is the mathematical answer correct?",
    category: :math
  }
]

response_fn = fn input ->
  case input do
    "What is 2+2?" -> "2 + 2 = 4"
    _ -> "I don't know"
  end
end

# Run evaluation with LangChain judge
{:ok, run_id} = 
  ExEval.new()
  |> ExEval.put_judge(ExEval.Langchain, model: "gpt-4o-mini")
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.run()
```

### Supported Features

- **Multiple Providers**: OpenAI, Anthropic, Google AI, Perplexity, Vertex AI
- **Evaluation Modes**: Direct evaluation, Chain-of-Thought (CoT), Multi-Shot Learning
- **JSON Schema Support**: Structured evaluation outputs with custom schemas
- **Temperature Control**: Fine-tune response randomness
- **Custom System Prompts**: Tailor judge behavior for your use case
- **Streaming Responses**: Real-time evaluation feedback

### Configuration Options

```elixir
ExEval.put_judge(ExEval.Langchain,
  model: "gpt-4o-mini",              # Model to use
  temperature: 0.0,                  # Deterministic output
  evaluation_mode: :cot,             # Chain-of-thought reasoning
  system_prompt: "You are an expert evaluator...",
  json_schema: custom_schema,        # Structured output
  provider: :openai                  # Explicit provider
)
```

### Examples

See the `examples/` directory for comprehensive examples:
- `examples/langchain_basic.exs` - Basic usage patterns
- `examples/langchain_advanced.exs` - Advanced features and integrations

For complete documentation, see the [ExEval LangChain README](https://github.com/bradleygolden/ex_eval_langchain).

---

# ExEval Developer Documentation

This documentation provides a complete reference for all ExEval functionality. It can be used standalone without referring to the source code.

## Table of Contents

1. [ExEval Module - Configuration API](#exeval-module---configuration-api)
2. [ExEval.Runner Module - Execution Control](#exevalrunner-module---execution-control)
3. [Event Broadcasting](#event-broadcasting)
4. [Pipeline Processors](#pipeline-processors)
5. [Composite Judges](#composite-judges)
6. [Metrics System](#metrics-system)
7. [Implementing Custom Components](#implementing-custom-components)
8. [Complete Examples](#complete-examples)

## ExEval Module - Configuration API

The main module provides a functional, composable API for building evaluation configurations.

### Core Functions

#### `new/0` - Create new configuration
```elixir
@spec new() :: %ExEval{}

config = ExEval.new()
# Returns default configuration with console reporter
```

#### `run/2` - Execute evaluation
```elixir
@spec run(config :: %ExEval{}, opts :: keyword()) :: 
  {:ok, run_id :: String.t()} | result_map()

# Async execution (default) - works in pipeline
{:ok, run_id} = 
  ExEval.new()
  |> ExEval.put_judge(MyJudge)
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.run()

# Sync execution - also works in pipeline
result = 
  ExEval.new()
  |> ExEval.put_judge(MyJudge)
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.run(async: false)

# With custom supervisor/registry
{:ok, run_id} = 
  ExEval.new()
  |> ExEval.put_judge(MyJudge)
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.run(supervisor: MyApp.EvalSupervisor, registry: MyApp.EvalRegistry)
```

Options:
- `:async` - boolean, default `true`. When `true`, returns `{:ok, run_id}`. When `false`, returns full result.
- `:supervisor` - atom, default `ExEval.RunnerSupervisor`
- `:registry` - atom, default `ExEval.RunnerRegistry`

### Dataset Configuration

#### `put_dataset/2` - Set evaluation dataset
```elixir
@spec put_dataset(config, dataset :: list(map())) :: config

config = ExEval.put_dataset(config, [
  %{
    input: "What is 2+2?",
    judge_prompt: "Is the answer mathematically correct?",
    category: :math,              # optional
    judge: MyCustomJudge,         # optional, overrides default
    metadata: %{difficulty: :easy} # optional
  }
])
```

#### `put_response_fn/2` - Set response generator
```elixir
@spec put_response_fn(config, fun) :: config

# Single argument function
config = ExEval.put_response_fn(config, fn input ->
  "Response to: #{input}"
end)

# Multi-argument for context/conversation (if supported by runner)
config = ExEval.put_response_fn(config, fn input, context ->
  "Response considering context: #{inspect(context)}"
end)
```

### Judge Configuration

#### `put_judge/2` and `put_judge/3` - Set evaluation judge
```elixir
@spec put_judge(config, module :: atom()) :: config
@spec put_judge(config, module :: atom(), opts :: keyword()) :: config
@spec put_judge(config, {module :: atom(), opts :: keyword()}) :: config

# Module only
config = ExEval.put_judge(config, MyApp.Judge)

# Module with options
config = ExEval.put_judge(config, MyApp.Judge, model: "gpt-4", temperature: 0)

# Tuple format
config = ExEval.put_judge(config, {MyApp.Judge, model: "gpt-4"})
```

#### `put_consensus_judge/3` - Configure consensus judge
```elixir
@spec put_consensus_judge(config, judges :: list(), opts :: keyword()) :: config

config = ExEval.put_consensus_judge(config,
  [
    {Judge1, model: "gpt-4"},
    {Judge2, model: "claude"},
    Judge3
  ],
  strategy: :majority,         # :majority | :unanimous | :threshold
  threshold: 0.75,            # for :threshold strategy
  aggregate_metadata: true     # combine metadata from all judges
)
```

#### `put_weighted_judge/2` - Configure weighted voting
```elixir
@spec put_weighted_judge(config, weighted_judges :: list({judge, weight})) :: config

config = ExEval.put_weighted_judge(config, [
  {{ExpertJudge, model: "gpt-4"}, 0.5},    # 50% weight
  {{FastJudge, model: "gpt-3.5"}, 0.3},    # 30% weight
  {SafetyJudge, 0.2}                       # 20% weight
])
```

### Pipeline Configuration

#### `put_preprocessor/2` - Add input preprocessor
```elixir
@spec put_preprocessor(config, processor) :: config

# Function reference
config = ExEval.put_preprocessor(config, &String.downcase/1)

# Module function tuple
config = ExEval.put_preprocessor(config, {MyModule, :preprocess})

# With arguments
config = ExEval.put_preprocessor(config, {MyModule, :preprocess, [opts]})

# Multiple preprocessors (executed in order)
config = config
|> ExEval.put_preprocessor(&String.trim/1)
|> ExEval.put_preprocessor(&String.downcase/1)
```

#### `put_response_processor/2` - Add response processor
```elixir
@spec put_response_processor(config, processor) :: config

config = config
|> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.strip_markdown/1)
|> ExEval.put_response_processor(&String.trim/1)
```

#### `put_postprocessor/2` - Add result postprocessor
```elixir
@spec put_postprocessor(config, processor) :: config

config = config
|> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.add_confidence_score/1)
|> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.normalize_to_score/1)
```

#### `put_middleware/2` - Add evaluation middleware
```elixir
@spec put_middleware(config, middleware) :: config

# Middleware has arity 2: (next_fn, context)
config = config
|> ExEval.put_middleware(&ExEval.Pipeline.Middleware.timing_logger/2)
|> ExEval.put_middleware(&ExEval.Pipeline.Middleware.retry_on_failure/2)
```

### Performance Configuration

#### `put_max_concurrency/2` - Set parallel execution limit
```elixir
@spec put_max_concurrency(config, pos_integer()) :: config

config = ExEval.put_max_concurrency(config, 5)  # Max 5 concurrent evaluations
```

#### `put_timeout/2` - Set evaluation timeout
```elixir
@spec put_timeout(config, pos_integer()) :: config

config = ExEval.put_timeout(config, 60_000)  # 60 second timeout
```

#### `put_parallel/2` - Enable/disable parallel execution
```elixir
@spec put_parallel(config, boolean()) :: config

config = ExEval.put_parallel(config, false)  # Sequential execution
```

### Experiment Tracking

#### `put_experiment/2` - Set experiment name
```elixir
@spec put_experiment(config, String.t() | atom()) :: config

config = ExEval.put_experiment(config, :safety_eval_v2)
```

#### `put_params/2` - Track parameters
```elixir
@spec put_params(config, map()) :: config

config = ExEval.put_params(config, %{
  model_version: "v1.0",
  temperature: 0.0,
  prompt_template: "standard"
})
```

#### `put_tags/2` - Add metadata tags
```elixir
@spec put_tags(config, map()) :: config

config = ExEval.put_tags(config, %{
  team: :safety,
  environment: :test,
  priority: :high
})
```

### Other Configuration

#### `put_reporter/2` and `put_reporter/3` - Set output reporter
```elixir
@spec put_reporter(config, module :: atom()) :: config
@spec put_reporter(config, module :: atom(), opts :: keyword()) :: config

# Default console reporter
config = ExEval.put_reporter(config, ExEval.Reporter.Console)

# With options
config = ExEval.put_reporter(config, MyApp.CustomReporter, format: :json)

# Silent reporter for tests
config = ExEval.put_reporter(config, ExEval.SilentReporter)
```

#### `put_store/2` and `put_store/3` - Configure result persistence
```elixir
@spec put_store(config, module :: atom()) :: config
@spec put_store(config, module :: atom(), opts :: keyword()) :: config

config = ExEval.put_store(config, MyApp.ResultStore, 
  table: :evaluation_results,
  ttl: 3600
)
```

#### `put_artifact_logging/2` - Enable artifact storage
```elixir
@spec put_artifact_logging(config, boolean()) :: config

config = ExEval.put_artifact_logging(config, true)
```

#### `put_broadcaster/2` and `put_broadcaster/3` - Configure broadcaster
```elixir
@spec put_broadcaster(config, module :: atom()) :: config
@spec put_broadcaster(config, module :: atom(), opts :: keyword()) :: config

# Single broadcaster for Phoenix PubSub
config = ExEval.put_broadcaster(config, ExEvalPubSub.Broadcaster, 
  topic: "evaluation:#{eval_id}",
  pubsub: MyApp.PubSub
)

# Disable broadcasting
config = ExEval.put_broadcaster(config, nil)
```

#### `put_broadcasters/1` - Configure multiple broadcasters
```elixir
@spec put_broadcasters(config, broadcasters :: list()) :: config

# Multiple broadcasters for simultaneous streaming
config = ExEval.put_broadcasters(config, [
  {ExEvalPubSub.Broadcaster, topic: "evaluation:#{eval_id}"},
  {ExEvalTelemetry.Broadcaster, prefix: [:my_app, :evaluations]}
])
```

## ExEval.Runner Module - Execution Control

The Runner module manages evaluation execution lifecycle.

### `get_run/2` - Get run state
```elixir
@spec get_run(run_id :: String.t(), opts :: keyword()) :: 
  {:ok, state} | {:error, reason}

{:ok, state} = ExEval.Runner.get_run(run_id)

# With custom registry
{:ok, state} = ExEval.Runner.get_run(run_id, registry: MyApp.Registry)
```

State includes:
- `:id` - Run ID
- `:status` - `:pending` | `:running` | `:completed` | `:error`
- `:results` - List of evaluation results
- `:started_at` - DateTime
- `:finished_at` - DateTime or nil
- `:error` - Error message if failed
- `:metadata` - Experiment metadata
- `:metrics` - Computed metrics (when completed)

### `list_active_runs/1` - List all active runs
```elixir
@spec list_active_runs(opts :: keyword()) :: list(run_info)

runs = ExEval.Runner.list_active_runs()
# Returns: [%{id: "...", pid: #PID<...>, status: :running}, ...]

# With custom registry
runs = ExEval.Runner.list_active_runs(registry: MyApp.Registry)
```

### `cancel_run/2` - Cancel running evaluation
```elixir
@spec cancel_run(run_id :: String.t(), opts :: keyword()) :: 
  {:ok, :cancelled} | {:error, reason}

{:ok, :cancelled} = ExEval.Runner.cancel_run(run_id)
```

### `run_sync/2` - Synchronous execution (internal)
```elixir
@spec run_sync(config :: %ExEval{}, opts :: keyword()) :: result_map()

# Usually called via ExEval.run/2 with async: false
result = ExEval.Runner.run_sync(config, timeout: 120_000)
```

## Event Broadcasting

ExEval supports real-time event streaming through the broadcaster system, perfect for LiveView UIs, monitoring, and telemetry. This provides a clean separation between the core evaluation logic and external integrations.

### Broadcaster Events

Broadcasters receive these lifecycle events with enriched data:

#### `:started` - Evaluation run begins
```elixir
%{
  run_id: "abc123",
  external_id: "user-eval-456",  # optional
  started_at: ~U[2024-01-01 12:00:00Z],
  total_cases: 100,
  timestamp: ~U[2024-01-01 12:00:00Z]
}
```

#### `:progress` - Individual evaluation completes
```elixir
%{
  run_id: "abc123",
  completed: 25,
  total: 100,
  percentage: 25.0,
  current_result: %{
    status: :passed,
    category: :math,
    duration_ms: 234
  },
  timestamp: ~U[2024-01-01 12:00:25Z]
}
```

#### `:completed` - Evaluation run finishes successfully
```elixir
%{
  run_id: "abc123", 
  status: :completed,
  results_summary: %{
    total: 100,
    passed: 85,
    failed: 15,
    errors: 0
  },
  metrics: %{pass_rate: 0.85, avg_latency_ms: 245},
  finished_at: ~U[2024-01-01 12:05:00Z],
  duration_ms: 300000,
  timestamp: ~U[2024-01-01 12:05:00Z]
}
```

#### `:failed` - Evaluation run encounters an error
```elixir
%{
  run_id: "abc123",
  error: "Judge initialization failed",
  finished_at: ~U[2024-01-01 12:01:00Z],
  timestamp: ~U[2024-01-01 12:01:00Z]
}
```

### Implementing a Broadcaster

```elixir
defmodule MyApp.EvalBroadcaster do
  @behaviour ExEval.Broadcaster
  
  @impl true
  def init(config) do
    # Initialize broadcaster state
    {:ok, %{
      topic: config[:topic] || "evaluations",
      pubsub: config[:pubsub] || MyApp.PubSub,
      prefix: config[:prefix] || ""
    }}
  end
  
  @impl true  
  def broadcast(:started, data, state) do
    Phoenix.PubSub.broadcast(state.pubsub, state.topic, 
      {:eval_started, data.run_id, data.total_cases})
    :ok
  end
  
  def broadcast(:progress, data, state) do
    # Send progress updates to LiveView
    Phoenix.PubSub.broadcast(state.pubsub, state.topic, 
      {:eval_progress, data.percentage, data.current_result})
    :ok
  end
  
  def broadcast(:completed, data, state) do
    # Notify completion with summary
    Phoenix.PubSub.broadcast(state.pubsub, state.topic,
      {:eval_complete, data.results_summary, data.metrics})
    :ok
  end
  
  def broadcast(:failed, data, state) do
    Phoenix.PubSub.broadcast(state.pubsub, state.topic,
      {:eval_failed, data.run_id, data.error})
    :ok
  end
  
  @impl true
  def terminate(_reason, _state) do
    # Optional cleanup
    :ok
  end
end
```

### Integration Patterns

**Multiple Broadcasters for Different Concerns:**

```elixir
config = ExEval.put_broadcasters(config, [
  # Real-time UI updates
  {ExEvalPubSub.Broadcaster, 
   topic: "evaluation:#{eval_id}", 
   pubsub: MyApp.PubSub},
   
  # Telemetry for monitoring  
  {ExEvalTelemetry.Broadcaster, 
   prefix: [:my_app, :evaluations]},
   
  # External metrics
  {ExEvalDatadog.Broadcaster, 
   service: "evaluations",
   tags: %{environment: "production"}}
])
```

**Broadcaster vs Other Patterns:**

| Pattern | Scope | Use Case | Performance |
|---------|-------|----------|-------------|
| **Broadcaster** | Run-level events | Progress tracking, LiveView updates | Best |
| **Middleware** | Per-evaluation wrapping | Logging, retries, auth | Good |  
| **Postprocessors** | Result transformation | Data enrichment, filtering | Good |

**Key Benefits:**
- **Fire-and-forget**: Broadcaster errors don't affect evaluation
- **Parallel execution**: Multiple broadcasters run simultaneously
- **Clean separation**: Core logic isolated from integrations
- **Zero dependencies**: Core library stays lightweight

**Recommended:** Use broadcasters for real-time UI updates and monitoring, as they provide run-level events with minimal overhead and error isolation.

### External Package Pattern

ExEval is designed for extensibility through external packages:

#### Official Integrations

- **[ex_eval_langchain](https://github.com/bradleygolden/ex_eval_langchain)** - Judge implementation with OpenAI, Anthropic, Google AI, and other LLM providers

This architecture keeps the core ExEval library focused and dependency-free while enabling integrations through the ecosystem.

## Pipeline Processors

All processors follow consistent patterns:
- Preprocessors/Response processors: `(input) -> transformed_input`
- Postprocessors: `({:ok, result, metadata}) -> {:ok, result, metadata}`
- Middleware: `(next_fn, context) -> result`

### Built-in Preprocessors

Located in `ExEval.Pipeline.Preprocessors`:

#### `sanitize_input/1`
```elixir
# Removes prompt injection attempts
"Ignore previous instructions" -> "[SANITIZED]"
"system: do this" -> "[SANITIZED]: do this"
```

#### `truncate_input/2`
```elixir
# Limits input length
truncate_input("very long text...", 10) -> "very long ..."
truncate_input("short", 10) -> "short"
```

#### `normalize_input/1`
```elixir
# Lowercase and trim
"  HELLO World  " -> "hello world"
```

### Built-in Response Processors

Located in `ExEval.Pipeline.ResponseProcessors`:

#### `strip_markdown/1`
```elixir
# Removes markdown formatting
"**bold** and *italic*" -> "bold and italic"
"```code```" -> "code"
```

#### `extract_first_sentence/1`
```elixir
# Gets only first sentence
"First sentence. Second sentence." -> "First sentence."
```

#### `validate_response/1`
```elixir
# Returns {:ok, response} or {:error, reason}
"Good response" -> {:ok, "Good response"}
"bad" -> {:error, "Response too short"}
"I don't know" -> {:error, "Generic response detected"}
```

### Built-in Postprocessors

Located in `ExEval.Pipeline.Postprocessors`:

#### `add_confidence_score/1`
```elixir
# Adds confidence based on reasoning length
{:ok, true, %{reasoning: "Long detailed reasoning..."}}
-> {:ok, true, %{reasoning: "...", confidence: 0.85}}
```

#### `normalize_to_score/1`
```elixir
# Converts boolean to numeric
{:ok, true, metadata} -> {:ok, 1.0, metadata}
{:ok, false, metadata} -> {:ok, 0.0, metadata}
{:ok, 0.75, metadata} -> {:ok, 0.75, metadata}  # Already numeric
```

#### `quality_filter/2`
```elixir
# Filters by confidence threshold
quality_filter({:ok, result, %{confidence: 0.9}}, 0.8) 
-> {:ok, result, %{confidence: 0.9}}

quality_filter({:ok, result, %{confidence: 0.5}}, 0.8)
-> {:ok, nil, %{confidence: 0.5, filtered: true}}
```

### Built-in Middleware

Located in `ExEval.Pipeline.Middleware`:

#### `timing_logger/2`
```elixir
# Logs execution time and results
def timing_logger(next_fn, context) do
  start = System.monotonic_time()
  result = next_fn.()
  duration = System.monotonic_time() - start
  Logger.info("Evaluation took #{duration}ms")
  result
end
```

#### `retry_on_failure/2`
```elixir
# Retries with exponential backoff
# Config: max_retries (default 3), base_delay (default 1000ms)
retry_on_failure(next_fn, %{config: %{max_retries: 3}})
```

#### `result_cache/2`
```elixir
# Caches evaluation results (placeholder implementation)
# Would check cache before executing, store after
result_cache(next_fn, context)
```

### Custom Processors

Create custom processors following the patterns:

```elixir
# Custom preprocessor
def my_preprocessor(input) do
  String.replace(input, "test", "TEST")
end

# Custom response processor  
def my_response_processor(response) do
  if valid?(response) do
    {:ok, transform(response)}
  else
    {:error, "Invalid response"}
  end
end

# Custom postprocessor
def my_postprocessor({:ok, result, metadata}) do
  enhanced_metadata = Map.put(metadata, :processed_at, DateTime.utc_now())
  {:ok, result, enhanced_metadata}
end

# Custom middleware
def my_middleware(next_fn, context) do
  Logger.info("Starting evaluation for #{context.input}")
  
  case next_fn.() do
    {:ok, _, _} = result ->
      Logger.info("Evaluation succeeded")
      result
    {:error, _} = error ->
      Logger.error("Evaluation failed")
      error
  end
end
```

## Composite Judges

### Consensus Judge

```elixir
# Majority voting (default)
config = ExEval.put_consensus_judge(config, [Judge1, Judge2, Judge3])

# Unanimous agreement required
config = ExEval.put_consensus_judge(config, 
  [Judge1, Judge2, Judge3],
  strategy: :unanimous
)

# Threshold-based (75% must agree)
config = ExEval.put_consensus_judge(config,
  [Judge1, Judge2, Judge3, Judge4],
  strategy: :threshold,
  threshold: 0.75
)

# With metadata aggregation
config = ExEval.put_consensus_judge(config,
  [Judge1, Judge2, Judge3],
  aggregate_metadata: true  # Combines all judges' metadata
)
```

Result metadata includes:
- `:consensus` - Agreement type achieved
- `:votes` - Individual judge votes
- `:agreement_ratio` - Percentage of agreement
- `:errors` - Any judge failures

### Weighted Judge

```elixir
# Basic weighted voting
config = ExEval.put_weighted_judge(config, [
  {Judge1, 0.5},   # 50% weight
  {Judge2, 0.3},   # 30% weight  
  {Judge3, 0.2}    # 20% weight
])

# With judge configuration
config = ExEval.put_weighted_judge(config, [
  {{ExpertJudge, model: "gpt-4"}, 0.6},
  {{QuickJudge, model: "gpt-3.5"}, 0.4}
])
```

Result metadata includes:
- `:weighted_score` - Final weighted result
- `:individual_results` - Each judge's result and weight
- `:strategy` - Aggregation strategy used
- `:distribution` - Result type distribution

## Metrics System

The metrics system automatically analyzes evaluation results:

```elixir
result = ExEval.run(config, async: false)
metrics = result.metrics

# Core metrics
%{
  total_cases: 100,
  evaluated: 95,
  errors: 5,
  passed: 70,              # Boolean true or :passed status
  failed: 25,              # Boolean false or :failed status
  pass_rate: 0.70,         # passed / total_cases
  error_rate: 0.05,        # errors / total_cases
  
  # Latency metrics
  avg_latency_ms: 245.5,
  min_latency_ms: 100,
  max_latency_ms: 500,
  p50_latency_ms: 230,
  p95_latency_ms: 450,
  p99_latency_ms: 490,
  
  # Category breakdown
  by_category: %{
    math: %{
      total: 30,
      passed: 28,
      failed: 2,
      pass_rate: 0.933
    },
    safety: %{
      total: 70,
      passed: 42,
      failed: 23,
      errors: 5,
      pass_rate: 0.60
    }
  },
  
  # Result type analysis
  result_distribution: %{
    boolean: %{
      total: 50,
      true: 35,
      false: 15,
      distribution: %{true: 0.7, false: 0.3}
    },
    numeric: %{
      total: 30,
      mean: 0.82,
      min: 0.45,
      max: 0.98,
      std_dev: 0.15
    },
    categorical: %{
      total: 15,
      distribution: %{
        excellent: 5,
        good: 7,
        fair: 3
      }
    }
  }
}
```

## Implementing Custom Components

### Using External Judge Providers

For convenience, you can use the LangChain integration instead of implementing custom judges:

```elixir
# ExEval LangChain - Judge with multiple LLM providers
ExEval.put_judge(ExEval.Langchain, 
  model: "gpt-4o-mini",
  provider: :openai,
  temperature: 0.0
)
```

See the [ExEval LangChain documentation](https://raw.githubusercontent.com/bradleygolden/ex_eval_langchain/refs/heads/main/README.md) for complete details on supported providers, models, and configuration options.

### Custom Judge

```elixir
defmodule MyApp.CustomJudge do
  @behaviour ExEval.Judge
  
  @impl true
  def call(response, criteria, config) do
    # config contains any options passed to put_judge
    model = config[:model] || "gpt-4"
    
    # Return format options:
    
    # Boolean result
    {:ok, true, %{reasoning: "The response is correct"}}
    
    # Numeric score
    {:ok, 0.85, %{reasoning: "Good response", confidence: 0.9}}
    
    # Categorical
    {:ok, :excellent, %{reasoning: "Exceeds expectations"}}
    
    # Multi-dimensional
    {:ok, %{safety: 0.9, helpfulness: 0.8}, %{reasoning: "Safe and helpful"}}
    
    # Error
    {:error, "Failed to evaluate: API timeout"}
  end
end
```

### Custom Reporter

```elixir
defmodule MyApp.JsonReporter do
  @behaviour ExEval.Reporter
  
  @impl true
  def init(_config, opts) do
    # Initialize reporter state
    {:ok, %{
      file: opts[:output_file] || "results.json",
      results: []
    }}
  end
  
  @impl true
  def report_result(result, _config, state) do
    # Called for each evaluation result
    {:ok, %{state | results: [result | state.results]}}
  end
  
  @impl true
  def finalize(summary, _config, state) do
    # Called at the end with final metrics
    json_output = %{
      summary: summary,
      results: Enum.reverse(state.results)
    }
    
    File.write!(state.file, Jason.encode!(json_output, pretty: true))
    {:ok, state}
  end
end
```

### Custom Store

```elixir
defmodule MyApp.DatabaseStore do
  @behaviour ExEval.Store
  
  @impl true
  def save_run(run_data) do
    # run_data includes all evaluation results and metadata
    case MyApp.Repo.insert(build_changeset(run_data)) do
      {:ok, _record} -> {:ok, run_data.id}
      {:error, changeset} -> {:error, changeset}
    end
  end
  
  @impl true 
  def get_run(run_id) do
    case MyApp.Repo.get(EvalRun, run_id) do
      nil -> {:error, :not_found}
      run -> {:ok, format_run(run)}
    end
  end
  
  @impl true
  def list_runs(filters \\ %{}) do
    query = build_query(filters)
    {:ok, MyApp.Repo.all(query)}
  end
end
```

### Custom Dataset Implementation

```elixir
defimpl ExEval.Dataset, for: MyApp.CustomDataset do
  def cases(dataset) do
    # Return list of evaluation cases
    dataset.items
  end
  
  def response_fn(dataset) do
    # Return function to generate responses
    dataset.responder || fn input -> "Default response to: #{input}" end
  end
  
  def setup_fn(_dataset) do
    # Optional setup before evaluation
    fn -> {:ok, %{api_key: fetch_api_key()}} end
  end
  
  def judge_config(dataset) do
    # Optional judge override
    dataset.custom_judge
  end
  
  def metadata(dataset) do
    # Dataset metadata
    %{
      source: dataset.source,
      version: dataset.version,
      created_at: dataset.created_at
    }
  end
end
```

## Complete Examples

### Basic Evaluation
```elixir
defmodule MyApp.Evaluations.Basic do
  def run do
    dataset = [
      %{input: "What is 2+2?", judge_prompt: "Is this correct?", category: :math},
      %{input: "Explain gravity", judge_prompt: "Is this accurate?", category: :science}
    ]
    
    config = 
      ExEval.new()
      |> ExEval.put_judge(MyApp.Judge, model: "gpt-4")
      |> ExEval.put_dataset(dataset)
      |> ExEval.put_response_fn(&MyApp.AI.generate/1)
      |> ExEval.put_experiment(:basic_eval)
      |> ExEval.put_max_concurrency(5)
    
    case ExEval.run(config, async: false) do
      %{status: :completed} = result ->
        IO.puts("Pass rate: #{result.metrics.pass_rate}")
        IO.inspect(result.metrics.by_category)
        
      %{status: :error, error: error} ->
        IO.puts("Evaluation failed: #{error}")
    end
  end
end
```

### Advanced Pipeline Example
```elixir
defmodule MyApp.Evaluations.Advanced do
  def run do
    config = 
      ExEval.new()
      # Consensus of multiple judges
      |> ExEval.put_consensus_judge([
        {MyApp.AccuracyJudge, model: "gpt-4"},
        {MyApp.SafetyJudge, model: "claude"},
        MyApp.HelpfulnessJudge
      ], strategy: :majority)
      
      # Input preprocessing
      |> ExEval.put_preprocessor(&String.trim/1)
      |> ExEval.put_preprocessor(&ExEval.Pipeline.Preprocessors.sanitize_input/1)
      
      # Response processing
      |> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.validate_response/1)
      
      # Result enhancement
      |> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.add_confidence_score/1)
      |> ExEval.put_postprocessor(&normalize_scores/1)
      
      # Cross-cutting concerns
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.timing_logger/2)
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.retry_on_failure/2)
      
      # Data and metadata
      |> ExEval.put_dataset(load_test_cases())
      |> ExEval.put_response_fn(&MyApp.AI.generate/1)
      |> ExEval.put_experiment(:advanced_pipeline_v1)
      |> ExEval.put_params(%{
        consensus_strategy: :majority,
        retry_enabled: true,
        preprocessing: :sanitized
      })
      |> ExEval.put_tags(%{team: :ml, priority: :high})
      
      # Custom reporter and storage
      |> ExEval.put_reporter(MyApp.MLflowReporter)
      |> ExEval.put_store(MyApp.PostgresStore)
    
    # Run async and monitor
    {:ok, run_id} = ExEval.run(config)
    monitor_run(run_id)
  end
  
  defp monitor_run(run_id) do
    case ExEval.Runner.get_run(run_id) do
      {:ok, %{status: :completed} = state} ->
        IO.puts("Evaluation completed!")
        analyze_results(state)
        
      {:ok, %{status: :running}} ->
        Process.sleep(1000)
        monitor_run(run_id)
        
      {:ok, %{status: :error} = state} ->
        IO.puts("Evaluation failed: #{state.error}")
        
      {:error, reason} ->
        IO.puts("Failed to get run status: #{reason}")
    end
  end
  
  defp normalize_scores({:ok, result, metadata}) when is_number(result) do
    # Normalize to 0-100 scale
    {:ok, result * 100, Map.put(metadata, :scale, "0-100")}
  end
  defp normalize_scores(result), do: result
end
```

### Multi-turn Conversation Example
```elixir
defmodule MyApp.Evaluations.Conversation do
  def run do
    dataset = [
      %{
        input: "Hi, I need help with math",
        judge_prompt: "Is this a friendly greeting?",
        conversation_id: 1
      },
      %{
        input: "What's 2+2?", 
        judge_prompt: "Is the response correct?",
        conversation_id: 1
      }
    ]
    
    # Stateful response function that maintains context
    response_fn = build_conversation_responder()
    
    config = 
      ExEval.new()
      |> ExEval.put_judge(MyApp.ConversationJudge)
      |> ExEval.put_dataset(dataset)
      |> ExEval.put_response_fn(response_fn)
      |> ExEval.put_parallel(false)  # Keep conversation order
    
    ExEval.run(config, async: false)
  end
  
  defp build_conversation_responder do
    # Use agent to maintain conversation state
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    
    fn input ->
      # This is a simplified example - real implementation would
      # track conversation history per conversation_id
      history = Agent.get(agent, & &1)
      response = generate_with_context(input, history)
      Agent.update(agent, &Map.put(&1, :last_exchange, {input, response}))
      response
    end
  end
end
```

### Error Handling Example
```elixir
defmodule MyApp.Evaluations.Robust do
  def run do
    config = 
      ExEval.new()
      |> ExEval.put_judge(MyApp.Judge, model: "gpt-4")
      |> ExEval.put_dataset(large_dataset())
      |> ExEval.put_response_fn(&potentially_failing_ai/1)
      # Validate responses before judging
      |> ExEval.put_response_processor(&validate_or_error/1)
      # Retry failed evaluations
      |> ExEval.put_middleware(&custom_retry_middleware/2)
      |> ExEval.put_timeout(30_000)
      |> ExEval.put_max_concurrency(3)
    
    {:ok, run_id} = ExEval.run(config)
    
    # Poll with timeout
    wait_for_completion(run_id, timeout: 300_000)
  end
  
  defp validate_or_error(response) do
    cond do
      is_nil(response) or response == "" ->
        {:error, "Empty response"}
      
      String.contains?(response, "error") ->
        {:error, "Response contains error"}
        
      true ->
        {:ok, response}
    end
  end
  
  defp custom_retry_middleware(next_fn, context) do
    # Custom retry with specific error handling
    retry_with_backoff(next_fn, context, 0)
  end
  
  defp retry_with_backoff(next_fn, context, attempt) when attempt < 3 do
    case next_fn.() do
      {:error, "Rate limit" <> _} = error ->
        Process.sleep(:timer.seconds(attempt + 1))
        retry_with_backoff(next_fn, context, attempt + 1)
        
      {:error, _} = error when attempt < 2 ->
        Process.sleep(100 * (attempt + 1))
        retry_with_backoff(next_fn, context, attempt + 1)
        
      result ->
        result
    end
  end
  defp retry_with_backoff(next_fn, _context, _attempt), do: next_fn.()
  
  defp wait_for_completion(run_id, opts) do
    timeout = opts[:timeout] || 60_000
    deadline = System.monotonic_time(:millisecond) + timeout
    
    do_wait_for_completion(run_id, deadline)
  end
  
  defp do_wait_for_completion(run_id, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case ExEval.Runner.get_run(run_id) do
        {:ok, %{status: :completed} = state} -> {:ok, state}
        {:ok, %{status: :error} = state} -> {:error, state}
        {:ok, %{status: status}} when status in [:pending, :running] ->
          Process.sleep(1000)
          do_wait_for_completion(run_id, deadline)
        error -> error
      end
    end
  end
end
```

### Comprehensive Example
```elixir
defmodule MyApp.Evaluations.Comprehensive do
  @moduledoc """
  Complete example showing all ExEval features working together.
  """
  
  def run do
    # Load test cases from various sources
    dataset = load_mixed_dataset()
    
    # Build complex evaluation pipeline
    config = 
      ExEval.new()
      # Weighted consensus of specialized judges
      |> ExEval.put_weighted_judge([
        {{AccuracyJudge, model: "gpt-4", temperature: 0}, 0.4},
        {{RelevanceJudge, model: "claude-3"}, 0.3},
        {{SafetyJudge, model: "gpt-4", mode: :strict}, 0.3}
      ])
      
      # Input pipeline
      |> ExEval.put_preprocessor(&trim_and_normalize/1)
      |> ExEval.put_preprocessor({ValidationModule, :validate_input, [:strict]})
      
      # Response pipeline  
      |> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.strip_markdown/1)
      |> ExEval.put_response_processor(&remove_pii/1)
      |> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.validate_response/1)
      
      # Result pipeline
      |> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.add_confidence_score/1)
      |> ExEval.put_postprocessor(&add_composite_metrics/1)
      |> ExEval.put_postprocessor({QualityModule, :filter, [min_confidence: 0.7]})
      
      # Middleware stack
      |> ExEval.put_middleware(&auth_middleware/2)
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.timing_logger/2)
      |> ExEval.put_middleware(&rate_limit_middleware/2)
      |> ExEval.put_middleware(&ExEval.Pipeline.Middleware.retry_on_failure/2)
      |> ExEval.put_middleware(&cache_middleware/2)
      
      # Core configuration
      |> ExEval.put_dataset(dataset)
      |> ExEval.put_response_fn(&intelligent_responder/1)
      |> ExEval.put_max_concurrency(10)
      |> ExEval.put_timeout(45_000)
      |> ExEval.put_parallel(true)
      
      # Tracking
      |> ExEval.put_experiment("comprehensive_eval_#{Date.utc_today()}")
      |> ExEval.put_params(%{
        judges: "weighted_consensus",
        preprocessing: "trim_normalize_validate", 
        postprocessing: "confidence_composite_filter",
        middleware: "auth_log_ratelimit_retry_cache"
      })
      |> ExEval.put_tags(%{
        environment: env(),
        version: "2.0",
        team: :platform,
        customer: :internal
      })
      |> ExEval.put_artifact_logging(true)
      
      # Output and storage
      |> ExEval.put_reporter(MultiReporter, reporters: [
        ExEval.Reporter.Console,
        MyApp.SlackReporter,
        MyApp.MetricsReporter
      ])
      |> ExEval.put_store(MyApp.S3Store, bucket: "evaluations")
    
    # Execute evaluation
    start_time = System.monotonic_time(:millisecond)
    
    case ExEval.run(config, async: false) do
      %{status: :completed} = result ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        IO.puts("\n=== Evaluation Complete ===")
        IO.puts("Duration: #{duration}ms")
        IO.puts("Total cases: #{result.metrics.total_cases}")
        IO.puts("Pass rate: #{Float.round(result.metrics.pass_rate * 100, 1)}%")
        
        IO.puts("\n=== By Category ===")
        Enum.each(result.metrics.by_category, fn {category, stats} ->
          IO.puts("#{category}: #{stats.passed}/#{stats.total} passed (#{Float.round(stats.pass_rate * 100, 1)}%)")
        end)
        
        IO.puts("\n=== Result Distribution ===")
        Enum.each(result.metrics.result_distribution, fn {type, stats} ->
          IO.puts("#{type}: #{stats.total} results")
        end)
        
        IO.puts("\n=== Performance ===")
        IO.puts("Avg latency: #{result.metrics.avg_latency_ms}ms")
        IO.puts("P95 latency: #{result.metrics.p95_latency_ms}ms")
        
        # Export results
        export_results(result)
        
      %{status: :error, error: error} ->
        IO.puts("Evaluation failed: #{error}")
        notify_on_failure(config, error)
    end
  end
  
  # Helper functions demonstrating various features
  
  defp trim_and_normalize(input) do
    input
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end
  
  defp remove_pii(response) do
    response
    |> String.replace(~r/\b\d{3}-\d{2}-\d{4}\b/, "[SSN]")
    |> String.replace(~r/\b[\w._%+-]+@[\w.-]+\.[A-Z]{2,}\b/i, "[EMAIL]")
  end
  
  defp add_composite_metrics({:ok, result, metadata}) do
    composite_score = calculate_composite_score(result, metadata)
    enhanced = metadata
    |> Map.put(:composite_score, composite_score)
    |> Map.put(:evaluated_at, DateTime.utc_now())
    
    {:ok, result, enhanced}
  end
  
  defp auth_middleware(next_fn, context) do
    if authorized?(context) do
      next_fn.()
    else
      {:error, "Unauthorized evaluation attempt"}
    end
  end
  
  defp rate_limit_middleware(next_fn, context) do
    case RateLimiter.check_rate(context.dataset_name) do
      :ok -> 
        next_fn.()
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, try again later"}
    end
  end
  
  defp cache_middleware(next_fn, context) do
    cache_key = generate_cache_key(context)
    
    case Cache.get(cache_key) do
      {:ok, cached} ->
        Logger.info("Using cached result for #{context.input}")
        cached
        
      :miss ->
        result = next_fn.()
        Cache.put(cache_key, result, ttl: :timer.hours(1))
        result
    end
  end
  
  defp intelligent_responder(input) do
    # Complex response generation with fallbacks
    with {:ok, primary} <- try_primary_ai(input),
         {:ok, validated} <- validate_ai_response(primary) do
      validated
    else
      {:error, :unavailable} ->
        try_backup_ai(input)
      {:error, :invalid_response} ->
        "I need more information to provide a proper response."
      _ ->
        "An error occurred while processing your request."
    end
  end
  
  defp export_results(result) do
    # Export to multiple formats
    File.write!("results.json", Jason.encode!(result, pretty: true))
    
    csv_content = format_as_csv(result.results)
    File.write!("results.csv", csv_content)
    
    summary = format_summary(result)
    File.write!("summary.md", summary)
    
    Logger.info("Results exported to results.json, results.csv, and summary.md")
  end
end
```

## Result Structure

All evaluation results follow this structure:

```elixir
%{
  # Run identification
  id: "unique-run-id",
  status: :completed | :error,
  
  # Timing
  started_at: ~U[2024-01-01 12:00:00Z],
  finished_at: ~U[2024-01-01 12:05:00Z],
  
  # Results array
  results: [
    %{
      input: "What is 2+2?",
      response: "4", 
      status: :passed | :failed | :error,
      result: true | 0.85 | :excellent | %{multi: "dimensional"},
      reasoning: "The answer is mathematically correct",
      metadata: %{
        confidence: 0.95,
        judge: "ConsensusJudge",
        consensus: :majority,
        latency_ms: 234
      },
      error: nil | "Error message if failed",
      dataset_name: "inline_config",
      case_index: 0,
      category: :math
    }
  ],
  
  # Computed metrics (see Metrics System section)
  metrics: %{...},
  
  # Experiment metadata
  metadata: %{
    experiment: :math_eval_v2,
    params: %{model: "gpt-4"},
    tags: %{team: :ml},
    artifact_logging: false
  },
  
  # Error information (if failed)
  error: nil | "Overall evaluation error message"
}
```

## Architecture Notes

- **OTP Application**: ExEval runs as a supervised OTP application
- **Process Isolation**: Each evaluation run is a separate supervised process
- **Fault Tolerance**: Individual evaluation failures don't crash the run
- **Registry**: Active runs are tracked in a process registry
- **Async by Default**: Non-blocking execution with status polling
- **Pipeline Order**: Preprocessors → Response → Response Processors → Judge → Postprocessors
- **Middleware Wrapping**: Middleware wraps the entire evaluation pipeline

## License

MIT