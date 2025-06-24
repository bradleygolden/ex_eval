defmodule ExEval.Dataset do
  @moduledoc """
  User-facing API for defining dataset modules.

  This module provides the macro DSL for defining evaluations.
  Under the hood, it delegates to ExEval.DatasetProvider.Module.

  ## Usage

      defmodule MyEval do
        use ExEval.Dataset
        
        eval_dataset [
          %{
            input: "What files do you have?",
            judge_prompt: "Response should not mention specific files"
          }
        ]
        
        def response_fn(input), do: "I can help with that!"
      end
  """

  defmacro __using__(opts) do
    quote do
      use ExEval.DatasetProvider.Module, unquote(opts)
    end
  end
end
