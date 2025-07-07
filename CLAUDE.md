# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Usage Rules

For detailed usage guidelines and best practices, see [usage-rules.md](./usage-rules.md). This file contains comprehensive rules for:
- Writing inline evaluation configurations
- Configuring the evaluation environment
- Creating effective judge prompts
- Running evaluations with ExEval.run/1 and ExEval.run_async/1
- Implementing custom judge providers

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

# Run evaluations (using inline configuration)
# See examples/ directory for sample scripts
# ExEval.run(config)             # Run evaluations asynchronously (default)
# ExEval.run(config, async: false)  # Run evaluations synchronously
```

## Architecture Overview

ExEval is the core evaluation framework for AI/LLM applications using the LLM-as-judge pattern. It provides an OTP application with supervision tree for managing async evaluation runs, with a clean functional API for inline configuration.

**Note: This repository contains only the core framework. External judge providers (like LangChain integrations) are maintained in separate repositories.**

### OTP Application Structure

The `ExEval.Application` starts a supervision tree with:
- **ExEval.RunnerRegistry** - Registry for tracking active evaluation runs by ID
- **ExEval.RunnerSupervisor** - DynamicSupervisor for spawning runner processes

The architecture consists of:

### Core Components

1. **ExEval.Dataset** - Protocol for handling evaluation datasets
   - Supports inline configuration via Maps
   - `cases/1` - Returns list of evaluation cases
   - `response_fn/1` - Returns response function for generating AI responses
   - `setup_fn/1` - Optional context setup function
   - `judge_config/1` - Optional judge configuration override
   - `metadata/1` - Returns dataset metadata

2. **ExEval.Evaluator** - Orchestrates the evaluation process by:
   - Building prompts that combine criteria and responses
   - Calling the configured judge provider (LLM) to judge responses
   - Parsing YES/NO judgments with reasoning

3. **ExEval.Runner** - Async-first GenServer implementation for executing evaluation suites:
   - **Async execution**: `run/1` returns `{:ok, run_id}` immediately
   - **Sync execution**: `run_sync/1` for blocking execution with timeout support
   - **Process supervision**: All runners are supervised by `ExEval.RunnerSupervisor`
   - **Registry tracking**: Active runs tracked in `ExEval.RunnerRegistry`
   - **Real-time updates**: Broadcasts progress via Phoenix.PubSub
   - **Lifecycle management**: `get_run/2`, `list_active_runs/1`, `cancel_run/2`
   - **Parallel execution**: Configurable concurrency with Task.async_stream
   - **Multi-turn conversations**: Functional state passing for conversation history
   - **Run metadata**: Custom metadata support for tracking and filtering

4. **Judge System** - Pluggable LLM provider interface:
   - `ExEval.Judge` behavior defines the contract  
   - Tests use inline mock modules for isolation
   - External judge providers available as separate packages

5. **Reporter System** - Pluggable output and monitoring interface:
   - `ExEval.Reporter` behavior for custom output formats
   - `ExEval.Reporter.Console` - Default colored console output

### Directory Structure

- `lib/ex_eval/` - Core framework code
  - `lib/ex_eval/reporter/` - Reporter implementations (Console)
- `test/` - Unit tests for the framework

### Key Design Patterns

1. **Inline Configuration**: Req-style functional API where datasets and response functions are defined directly in the configuration struct, eliminating the need for separate modules.

2. **Protocol-based Extensibility**: The Dataset protocol allows different data sources while maintaining a consistent interface.

3. **LLM-as-Judge Pattern**: Evaluations use natural language criteria judged by an LLM, returning structured YES/NO responses with reasoning.

4. **Functional State Management**: Multi-turn conversations pass conversation history explicitly through function arguments, avoiding global state. Response functions can receive up to 3 arguments: (input, context, conversation_history).

### Adding New Features

When extending ExEval:

1. **New Judge Providers**: Implement the `ExEval.Judge` behavior with a `call/3` function
2. **New Dataset Sources**: Implement the `ExEval.Dataset` protocol for custom data sources
3. **New Evaluation Options**: Update `ExEval` struct and `ExEval.Runner` to handle new options
4. **New Reporters**: Implement the `ExEval.Reporter` behavior with `init/2`, `report_result/3`, and `finalize/3` callbacks

### Testing Strategy

- Unit tests focus on core logic (Evaluator, Runner, etc.)
- Tests use inline mock modules for isolation and clarity

### External Integrations

ExEval provides a pluggable architecture that supports external packages:

- **Judge Providers**: External packages can implement the `ExEval.Judge` behavior for different LLM providers
- **Reporters**: External packages can implement the `ExEval.Reporter` behavior for different output formats and integrations
- **Dataset Sources**: Custom data sources can implement the `ExEval.Dataset` protocol

See the ExEval ecosystem packages for specific integrations (LangChain, Phoenix PubSub, etc.).

## Memory

- Do not use @spec