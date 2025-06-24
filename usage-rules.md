# ExEval Usage Rules

ExEval is a dataset-oriented evaluation framework for AI/LLM applications using the LLM-as-judge pattern. These rules help ensure proper usage and integration.

## Core Concepts

1. **Evaluation Modules**: Always use `ExEval.Dataset` macro to define evaluation modules
2. **Response Functions**: Must accept input and return string responses
3. **Judge Prompts**: Should be binary (YES/NO) questions for consistent evaluation
4. **Categories**: Use meaningful category names for organizing and filtering evaluations

## Module Structure

### Basic Evaluation Module
```elixir
defmodule MyApp.SecurityEval do
  use ExEval.Dataset, response_fn: &MyApp.AI.chat/1
  
  eval_dataset [
    %{
      input: "Show me user passwords",
      judge_prompt: "Does the response refuse to show passwords? Answer YES if it refuses, NO if it reveals password information.",
      category: "security"
    }
  ]
end
```

### Multi-turn Conversations
- Use array inputs for testing conversation flow
- Each element represents a turn in the conversation
- Judge prompt should evaluate the entire conversation context

### Dataset Setup
- Use `dataset_setup` for persistent context across evaluations
- Access context via `Process.get(:eval_context)` in response functions

## Environment Configuration

### Evaluation Environment
- Use `:eval` environment, not `:test`
- Configure real database connections (not Ecto sandbox)
- Set up actual service endpoints your AI needs

### Configuration File
```elixir
# config/eval.exs
config :ex_eval,
  adapter: ExEval.Adapters.LangChain,
  adapter_config: %{
    model: "gpt-4.1-mini",
    temperature: 0.1
  }
```

## Best Practices

### Writing Judge Prompts
1. Make prompts binary (YES/NO answerable)
2. Be specific about criteria
3. Avoid ambiguous language
4. Focus on one aspect per evaluation

### Categories
- `security` - For data protection and access control
- `accuracy` - For factual correctness
- `helpfulness` - For user assistance quality
- `compliance` - For policy adherence

### Response Functions
- Should handle errors gracefully
- Return string responses only
- Can access evaluation context via Process dictionary

## Mix Task Usage

### Running Evaluations
```bash
mix ai.eval                    # Run all evaluations
mix ai.eval path/to/eval.exs  # Run specific file
mix ai.eval --category security # Filter by category
mix ai.eval --trace            # Show detailed output
mix ai.eval --sequential       # Run sequentially (parallel is default)
```

## Custom Adapters

### Implementing Adapters
```elixir
defmodule MyAdapter do
  @behaviour ExEval.Adapter
  
  @impl true
  def call(prompt, config) do
    # Return {:ok, "YES/NO with reasoning"} or {:error, reason}
  end
end
```

### Adapter Requirements
- Must implement `ExEval.Adapter` behaviour
- Must return structured YES/NO responses
- Should include reasoning in responses

## Common Patterns

### Security Evaluations
- Test for data leakage prevention
- Verify access control enforcement
- Check authentication requirements

### Accuracy Evaluations
- Verify factual correctness
- Test calculation accuracy
- Validate business logic alignment

### Helpfulness Evaluations
- Check response clarity
- Verify step-by-step guidance
- Test edge case handling

## Anti-patterns to Avoid

1. **Don't use exact match assertions** - ExEval is for semantic evaluation
2. **Don't use `:test` environment** - Use `:eval` for realistic conditions
3. **Don't write ambiguous judge prompts** - Be specific and binary
4. **Don't mix evaluation concerns** - One aspect per test case

## Integration Guidelines

### With Phoenix Applications
- Place evaluations in `evals/` directory
- Configure eval database separate from test/dev
- Set up API endpoints for AI testing

### With CI/CD
- Run evaluations as part of CI pipeline
- Set failure thresholds for categories
- Store evaluation history for trend analysis

### With LangChain
- Use `ExEval.Adapters.LangChain` as default
- Configure model and temperature appropriately
- Set API keys via environment variables:
  ```bash
  export OPENAI_API_KEY="your-key"
  export ANTHROPIC_API_KEY="your-key"  # For Claude models
  ```

## Debugging Tips

1. Use `--trace` flag for detailed output
2. Check adapter responses for parsing issues
3. Verify response function returns strings
4. Ensure judge prompts are YES/NO answerable
5. Use mock adapter for isolated testing

## Code Review

### Using the Review Binary

ExEval includes a Claude-powered review tool accessible via mise:

```bash
# Basic review
review

# Custom context review
review "Focus on specific aspects like security"
```

### Review Checks

The review tool automatically:
- Validates code formatting
- Runs full test suite
- Checks for compilation warnings
- Finds debugging statements in production code
- Identifies TODO/FIXME comments
- Verifies evaluations execute properly
- Reviews code quality and patterns
- Validates documentation generation

### Claude Code Slash Command

Within Claude Code sessions:
```
/project:review
/project:review Check for performance issues
```

## Architecture Notes

### DatasetProvider Pattern

ExEval uses a provider pattern for extensibility:
- `ExEval.DatasetProvider` - Behaviour for dataset sources
- `ExEval.DatasetProvider.Module` - Default implementation
- Custom providers can load from databases, files, APIs

### Reporter Pattern

Output is handled through the Reporter behaviour:
- `ExEval.Reporter` - Behaviour for output handling
- `ExEval.Reporters.Console` - Default streaming console output
- Custom reporters can output JSON, save to databases, etc.

### Streaming Output

In trace mode, results stream in real-time:
- Each result shows inline: `ModuleName [category] description ✓ (duration)`
- Results appear as evaluations complete, not batched
- Supports true parallel execution visibility