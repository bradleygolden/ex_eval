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

Implement custom judge providers by following the `ExEval.Judge` behavior.

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
config = 
  ExEval.new()
  |> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4")
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_experiment(:math_eval)

# Run asynchronously (default)
{:ok, run_id} = ExEval.run(config)

# Check status
{:ok, state} = ExEval.Runner.get_run(run_id)

# Or run synchronously
results = ExEval.run(config, async: false)

# Handle results
if results.status == :completed do
  IO.inspect(results.metrics)
else
  IO.puts("Evaluation failed: #{results.error}")
end
```

## Configuration Options

### Judge Configuration

```elixir
# Basic judge configuration
config = ExEval.new()
|> ExEval.put_judge(MyApp.CustomJudge)

# Judge with options
config = ExEval.new()
|> ExEval.put_judge(MyApp.CustomJudge, model: "gpt-4", temperature: 0.0)

# Tuple format
config = ExEval.new()
|> ExEval.put_judge({MyApp.CustomJudge, model: "gpt-4"})
```

### Performance Configuration

```elixir
config = ExEval.new()
|> ExEval.put_max_concurrency(5)    # Run 5 evaluations in parallel
|> ExEval.put_timeout(30_000)       # 30 second timeout per evaluation
|> ExEval.put_parallel(false)       # Run sequentially instead
```

### Async vs Sync Execution

```elixir
# Async execution (default) - returns immediately
{:ok, run_id} = ExEval.run(config)

# Poll for status
{:ok, state} = ExEval.Runner.get_run(run_id)
IO.puts("Status: #{state.status}")  # :pending, :running, :completed, :error

# List all active runs
active_runs = ExEval.Runner.list_active_runs()

# Cancel a running evaluation
{:ok, :cancelled} = ExEval.Runner.cancel_run(run_id)

# Sync execution - blocks until complete
results = ExEval.run(config, async: false)
```

### Experiment Tracking

```elixir
config = ExEval.new()
|> ExEval.put_experiment(:safety_eval_v2)   # Experiment name
|> ExEval.put_params(%{                     # Track parameters
  model_version: "v1.0",
  temperature: 0.0
})
|> ExEval.put_tags(%{                       # Add tags for filtering
  team: :safety,
  environment: :test
})
```

## Implementing Custom Judges

Create a custom judge by implementing the `ExEval.Judge` behavior:

```elixir
defmodule MyApp.CustomJudge do
  @behaviour ExEval.Judge

  @impl true
  def call(response, criteria, config) do
    # Your custom logic here
    # Return {:ok, result, metadata} or {:error, reason}
    
    # For boolean judges (pass/fail):
    {:ok, true, %{reasoning: "The response correctly answers the question"}}
    
    # For score-based judges:
    {:ok, 0.85, %{reasoning: "Good response", confidence: 0.9}}
    
    # For multi-dimensional judges:
    {:ok, %{safety: 0.9, helpfulness: 0.8}, %{reasoning: "Safe and helpful"}}
    
    # For categorical judges:
    {:ok, :excellent, %{reasoning: "Exceeds expectations", details: "..."}}
  end
end
```

### Judge Result Format

The judge must return a tuple with three elements:

1. **Status**: `:ok` for successful evaluation or `:error` for failures
2. **Result**: The evaluation result (boolean, number, atom, map, etc.)
3. **Metadata**: A map containing at least `:reasoning`, plus any additional metadata

Boolean results (`true`/`false`) are automatically converted to `:passed`/`:failed` status in the runner, with the reasoning extracted to the top level of the result.

## Metrics and Result Analysis

ExEval automatically computes comprehensive metrics from your evaluation results:

```elixir
results = ExEval.run(config, async: false)

# Access computed metrics
results.metrics
# => %{
#   total_cases: 10,
#   evaluated: 9,
#   errors: 1,
#   passed: 7,           # Count of boolean true results or :passed status
#   failed: 2,           # Count of boolean false results or :failed status  
#   pass_rate: 0.7,      # Passed / total_cases (including errors)
#   avg_latency_ms: 245.5,
#   p95_latency_ms: 450,
#   by_category: %{...},
#   result_distribution: %{
#     boolean: %{total: 9, true: 7, false: 2},
#     numeric: %{total: 3, mean: 0.82, min: 0.65, max: 0.95}
#   }
# }
```

The metrics system automatically:
- Detects result types (boolean, numeric, categorical, multi-dimensional)
- Calculates appropriate statistics for each type
- Groups metrics by category
- Tracks latency percentiles
- Maintains backwards compatibility with boolean pass/fail metrics

## Example Output

```
Running ExEval with seed: 123456

.✓

Finished in 1.23 seconds
1 evaluation, 0 failures

Randomized with seed 123456
```

## Advanced Features

### Composite Judges

Combine multiple judges for more robust evaluations:

```elixir
# Consensus judge - requires majority agreement
config = ExEval.new()
|> ExEval.put_consensus_judge([
  {Judge1, model: "gpt-4"},
  {Judge2, model: "claude"},
  {Judge3, model: "gemini"}
], strategy: :majority)

# Weighted voting - assign importance to different judges
config = ExEval.new()
|> ExEval.put_weighted_judge([
  {{ExpertJudge, model: "gpt-4"}, 0.5},    # 50% weight
  {{FastJudge, model: "gpt-3.5"}, 0.3},   # 30% weight
  {{SafetyJudge, model: "claude"}, 0.2}   # 20% weight
])
```

### Pipeline Processors

Transform data at any stage of evaluation:

```elixir
config = ExEval.new()
# Preprocess inputs before response generation
|> ExEval.put_preprocessor(&String.downcase/1)
|> ExEval.put_preprocessor(&ExEval.Pipeline.Preprocessors.sanitize_input/1)

# Process responses before judging
|> ExEval.put_response_processor(&ExEval.Pipeline.ResponseProcessors.strip_markdown/1)

# Transform judge results
|> ExEval.put_postprocessor(&ExEval.Pipeline.Postprocessors.add_confidence_score/1)

# Add cross-cutting concerns with middleware
|> ExEval.put_middleware(&ExEval.Pipeline.Middleware.timing_logger/2)
```

### Built-in Processors

**Preprocessors:**
- `sanitize_input/1` - Remove prompt injection attempts
- `truncate_input/2` - Limit input length
- `normalize_input/1` - Lowercase and trim whitespace

**Response Processors:**
- `strip_markdown/1` - Remove markdown formatting
- `extract_first_sentence/1` - Get only the first sentence
- `validate_response/1` - Check response quality

**Postprocessors:**
- `add_confidence_score/1` - Add confidence based on metadata
- `normalize_to_score/1` - Convert boolean to numeric (0.0/1.0)
- `quality_filter/2` - Filter low-quality results

**Middleware:**
- `timing_logger/2` - Log evaluation timing
- `retry_on_failure/2` - Retry with exponential backoff
- `result_cache/2` - Cache evaluation results

## Architecture

ExEval is built around a supervised OTP application:

- **Async-first execution** - Returns immediately with run ID by default
- **Process supervision** - Fault-tolerant evaluation runs  
- **Experiment tracking** - MLflow-inspired run metadata
- **Flexible judge results** - Support any result type, not just boolean
- **Composable design** - Mix and match judges, processors, and reporters
- **Pipeline architecture** - Transform data at any evaluation stage

## Contributing

Contributions welcome! This is the core ExEval framework.

## License

MIT