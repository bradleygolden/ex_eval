defmodule ExEval.Dataset do
  @moduledoc """
  Dataset-oriented evaluation framework for LLM testing.

  Allows defining evaluations as data rather than test functions,
  similar to MLflow's LLM evaluation approach.
  """

  defmacro __using__(opts) do
    quote do
      import ExEval.Dataset

      @dataset_opts unquote(opts)
      @eval_cases []

      @before_compile ExEval.Dataset
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
