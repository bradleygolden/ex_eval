defmodule ExEval.DatasetProvider.TestMock do
  @moduledoc """
  Mock dataset provider for testing.

  This provider returns predictable test data without file system dependencies,
  making tests fast and reliable.
  """

  @behaviour ExEval.DatasetProvider

  @impl ExEval.DatasetProvider
  def load(opts) do
    case Keyword.get(opts, :module) do
      :test_eval ->
        %{
          cases: [
            %{input: "test input 1", judge_prompt: "Does this work?", category: "basic"},
            %{input: "test input 2", judge_prompt: "Is this correct?", category: "advanced"}
          ],
          response_fn: fn _input -> "test response" end,
          judge_provider: ExEval.JudgeProvider.TestMock,
          config: %{mock_response: "YES\nTest passes"},
          setup_fn: nil,
          metadata: %{module: :test_eval}
        }

      :security_eval ->
        %{
          cases: [
            %{input: "security test", judge_prompt: "Is this secure?", category: "security"}
          ],
          response_fn: fn _input -> "secure response" end,
          judge_provider: nil,
          config: nil,
          setup_fn: nil,
          metadata: %{module: :security_eval}
        }

      :performance_eval ->
        %{
          cases: [
            %{
              input: "performance test 1",
              judge_prompt: "Is this fast?",
              category: "performance"
            },
            %{
              input: "performance test 2",
              judge_prompt: "Is this efficient?",
              category: "performance"
            },
            %{
              input: "performance test 3",
              judge_prompt: "Is this optimized?",
              category: "performance"
            }
          ],
          response_fn: fn _input -> "fast response" end,
          judge_provider: nil,
          config: nil,
          setup_fn: nil,
          metadata: %{module: :performance_eval}
        }

      _ ->
        raise ArgumentError,
              "Unknown module for MockDatasetProvider: #{inspect(Keyword.get(opts, :module))}"
    end
  end

  @impl ExEval.DatasetProvider
  def list_evaluations(_opts \\ []) do
    [:test_eval, :security_eval, :performance_eval]
  end

  @impl ExEval.DatasetProvider
  def get_evaluation_info(evaluation_id, _opts \\ []) do
    case evaluation_id do
      :test_eval ->
        {:ok,
         %{
           module: :test_eval,
           categories: ["basic", "advanced"],
           case_count: 2,
           cases: [
             %{input: "test input 1", judge_prompt: "Does this work?", category: "basic"},
             %{input: "test input 2", judge_prompt: "Is this correct?", category: "advanced"}
           ]
         }}

      :security_eval ->
        {:ok,
         %{
           module: :security_eval,
           categories: ["security"],
           case_count: 1,
           cases: [
             %{input: "security test", judge_prompt: "Is this secure?", category: "security"}
           ]
         }}

      :performance_eval ->
        {:ok,
         %{
           module: :performance_eval,
           categories: ["performance"],
           case_count: 3,
           cases: [
             %{
               input: "performance test 1",
               judge_prompt: "Is this fast?",
               category: "performance"
             },
             %{
               input: "performance test 2",
               judge_prompt: "Is this efficient?",
               category: "performance"
             },
             %{
               input: "performance test 3",
               judge_prompt: "Is this optimized?",
               category: "performance"
             }
           ]
         }}

      _ ->
        {:error, :not_an_evaluation_module}
    end
  end

  @impl ExEval.DatasetProvider
  def get_categories(_opts \\ []) do
    ["advanced", "basic", "performance", "security"]
  end

  @impl ExEval.DatasetProvider
  def list_evaluations_by_category(categories, _opts \\ []) when is_list(categories) do
    all_evals = [
      {:test_eval, ["basic", "advanced"]},
      {:security_eval, ["security"]},
      {:performance_eval, ["performance"]}
    ]

    all_evals
    |> Enum.filter(fn {_eval, eval_categories} ->
      Enum.any?(categories, &(&1 in eval_categories))
    end)
    |> Enum.map(fn {eval, _} -> eval end)
  end
end
