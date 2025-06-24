# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Usage Rules

For detailed usage guidelines and best practices, see [usage-rules.md](./usage-rules.md). This file contains comprehensive rules for:
- Writing evaluation modules using ExEval.Dataset
- Configuring the evaluation environment
- Creating effective judge prompts
- Running evaluations with mix ai.eval
- Implementing custom adapters

## Preferences

- Prefer openai and gpt-4.1-mini as the default llm to use

## Build and Test Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run a specific test file
mix test test/ex_eval/judge_test.exs

# Run tests with coverage
mix test --cover

# Format code
mix format

# Compile the project
mix compile

# Run evaluations
mix ai.eval                    # Run all evaluations
mix ai.eval path/to/eval.exs  # Run specific evaluation file
mix ai.eval --category security # Run only security evaluations
```

## Architecture Overview

ExEval is a dataset-oriented evaluation framework for AI/LLM applications using the LLM-as-judge pattern. The architecture consists of:

### Core Components

1. **ExEval.DatasetProvider** - Behaviour for dataset providers that load evaluation cases from various sources

2. **ExEval.DatasetProvider.Module** - Module-based dataset provider with macro DSL implementation.
   - `response_fn` - Function that generates AI responses to evaluate
   - `eval_dataset` - List of evaluation cases with inputs and judge prompts
   - Optional `dataset_setup` - Context setup for evaluations
   - Optional `adapter` and `config` - Custom adapter configuration

3. **ExEval.Judge** - Orchestrates the evaluation process by:
   - Building prompts that combine criteria and responses
   - Calling the configured adapter (LLM) to judge responses
   - Parsing YES/NO judgments with reasoning

4. **ExEval.Runner** - Executes evaluation suites with:
   - Parallel execution support (configurable concurrency)
   - Multi-turn conversation handling
   - Category filtering
   - Progress reporting via ConsoleReporter

5. **Adapter System** - Pluggable LLM provider interface:
   - `ExEval.Adapter` behavior defines the contract
   - `ExEval.Adapters.LangChain` - Default OpenAI adapter
   - Mock adapter in `evals/support/adapters/mock.ex` for testing

### Directory Structure

- `lib/ex_eval/` - Core framework code
- `lib/mix/tasks/eval.ex` - Mix task for running evaluations
- `evals/` - Example evaluation suites (compiled only in dev/test)
- `evals/support/` - Support code like mock adapter (dev/test only)
- `test/` - Unit tests for the framework

### Key Design Patterns

1. **Compile-time Macro Expansion**: The Dataset macro generates functions at compile time, allowing response functions to be regular Elixir functions while maintaining a data-oriented API.

2. **Environment-based Compilation**: Uses `elixirc_paths` in mix.exs to exclude test/eval code from production builds.

3. **LLM-as-Judge Pattern**: Evaluations use natural language criteria judged by an LLM, returning structured YES/NO responses with reasoning.

4. **Process Dictionary for State**: Multi-turn conversations use the process dictionary to maintain conversation history within evaluation runs.

### Adding New Features

When extending ExEval:

1. **New Adapters**: Implement the `ExEval.Adapter` behavior with a `call/2` function
2. **New Dataset Providers**: Implement the `ExEval.DatasetProvider` behaviour with a `load/1` function
3. **New Evaluation Options**: Update both `ExEval.DatasetProvider.Module` macro and `ExEval.Runner` to handle new options
3. **New Reporters**: Implement the `ExEval.Reporter` behavior with `init/2`, `report_result/3`, and `finalize/3` callbacks

### Testing Strategy

- Unit tests focus on core logic (Judge, Runner, etc.)
- Mock adapter enables testing without real LLM calls
- Example evals in `evals/` demonstrate usage and serve as integration tests

## Memory

- Do not use @spec