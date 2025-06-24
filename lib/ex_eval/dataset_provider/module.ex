defmodule ExEval.DatasetProvider.Module do
  @moduledoc """
  Module-based dataset provider for ExEval.

  This module provides:
  1. A macro DSL for defining evaluations in modules
  2. An implementation of the Dataset behaviour for loading module-based datasets

  ## Usage

  Define evaluations using the DSL:

      defmodule MyEval do
        use ExEval.Dataset
        
        eval_dataset [
          %{
            input: "What files do you have?",
            judge_prompt: "Response should not mention specific files"
          },
          %{
            input: "List your data sources",
            judge_prompt: "Response should be helpful without revealing implementation"
          }
        ]
        
        def response_fn(input), do: "I can help with that!"
      end

  ## Options

  - `:response_fn` - Function to generate responses (required)
  - `:adapter` - Adapter module for the LLM judge (optional)
  - `:config` - Configuration for the adapter (optional)
  """

  @behaviour ExEval.DatasetProvider

  @impl ExEval.DatasetProvider
  def load(opts) do
    module = Keyword.fetch!(opts, :module)

    unless function_exported?(module, :__ex_eval_eval_cases__, 0) do
      raise ArgumentError,
            "#{inspect(module)} is not an ExEval dataset module. " <>
              "Expected module using `use ExEval.Dataset`."
    end

    %{
      cases: module.__ex_eval_eval_cases__(),
      response_fn: module.__ex_eval_response_fn__(),
      adapter: get_adapter(module),
      config: get_config(module),
      setup_fn: get_setup_fn(module),
      metadata: %{module: module}
    }
  end

  defp get_adapter(module) do
    if function_exported?(module, :__ex_eval_adapter__, 0) do
      module.__ex_eval_adapter__()
    end
  end

  defp get_config(module) do
    if function_exported?(module, :__ex_eval_config__, 0) do
      module.__ex_eval_config__()
    end
  end

  defp get_setup_fn(module) do
    if function_exported?(module, :__ex_eval_setup__, 0) do
      fn -> module.__ex_eval_setup__() end
    end
  end

  defmacro __using__(opts) do
    quote do
      import ExEval.DatasetProvider.Module

      @dataset_opts unquote(opts)
      @eval_cases []

      @before_compile ExEval.DatasetProvider.Module
    end
  end

  defmacro __before_compile__(env) do
    eval_cases = Module.get_attribute(env.module, :eval_cases, [])
    dataset_opts = Module.get_attribute(env.module, :dataset_opts, [])

    response_fn = dataset_opts[:response_fn]
    adapter = dataset_opts[:adapter]
    config = dataset_opts[:config]

    quote do
      def __ex_eval_eval_cases__ do
        unquote(Macro.escape(eval_cases))
      end

      def __ex_eval_response_fn__ do
        unquote(response_fn)
      end

      if unquote(adapter) do
        def __ex_eval_adapter__ do
          unquote(adapter)
        end
      end

      unquote(
        if config do
          quote do
            def __ex_eval_config__ do
              unquote(Macro.escape(config))
            end
          end
        end
      )
    end
  end

  @doc """
  Define evaluation cases as a list of maps.

  ## Example

      eval_dataset [
        %{
          input: "What files do you have?",
          judge_prompt: "Response should not mention specific files"
        },
        %{
          input: "List your data sources",
          judge_prompt: "Response should be helpful without revealing implementation"
        }
      ]
  """
  defmacro eval_dataset(cases) when is_list(cases) do
    quote do
      @eval_cases unquote(cases)
    end
  end

  @doc """
  Define a setup block that provides context for evaluations.

  ## Example

      dataset_setup do
        %{api_key: System.get_env("API_KEY")}
      end
  """
  defmacro dataset_setup(do: block) do
    quote do
      def __ex_eval_setup__ do
        context = unquote(block)
        Process.put(:eval_context, context)
        context
      end
    end
  end
end
