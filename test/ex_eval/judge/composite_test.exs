defmodule ExEval.Judge.CompositeTest do
  use ExUnit.Case, async: true

  # Mock judges for testing
  defmodule AlwaysTrueJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:ok, true, %{reasoning: "Always true", source: "AlwaysTrueJudge"}}
    end
  end

  defmodule AlwaysFalseJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:ok, false, %{reasoning: "Always false", source: "AlwaysFalseJudge"}}
    end
  end

  defmodule ScoreJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, config) do
      score = config[:score] || 0.8
      {:ok, score, %{reasoning: "Score: #{score}", source: "ScoreJudge"}}
    end
  end

  defmodule CategoryJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, config) do
      category = config[:category] || :good
      {:ok, category, %{reasoning: "Category: #{category}", source: "CategoryJudge"}}
    end
  end

  defmodule ErrorJudge do
    @behaviour ExEval.Judge

    @impl true
    def call(_response, _criteria, _config) do
      {:error, "Judge failed"}
    end
  end

  describe "Consensus judge" do
    test "majority consensus with boolean judges" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysFalseJudge
        ],
        strategy: :majority
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == true
      assert metadata.consensus == true
      assert metadata.strategy == :majority
      assert metadata.agreement_ratio == 2 / 3
      assert metadata.total_judges == 3
      assert metadata.agreeing_judges == 2
    end

    test "unanimous consensus fails when not all agree" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysFalseJudge
        ],
        strategy: :unanimous
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == :no_consensus
      assert metadata.consensus == false
      assert metadata.strategy == :unanimous
      assert metadata.distribution == %{true => 2, false => 1}
    end

    test "unanimous consensus succeeds when all agree" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysTrueJudge
        ],
        strategy: :unanimous
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == true
      assert metadata.consensus == true
      assert metadata.agreement_ratio == 1.0
    end

    test "threshold consensus with 75% requirement" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysFalseJudge
        ],
        strategy: :threshold,
        threshold: 0.75
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == true
      assert metadata.consensus == true
      assert metadata.strategy == {:threshold, 0.75}
      assert metadata.agreement_ratio == 0.75
    end

    test "consensus with score judges" do
      config = %{
        judges: [
          {ScoreJudge, score: 0.9},
          {ScoreJudge, score: 0.9},
          {ScoreJudge, score: 0.7}
        ],
        strategy: :majority
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == 0.9
      assert metadata.consensus == true
      assert metadata.agreement_ratio == 2 / 3
    end

    test "consensus with category judges" do
      config = %{
        judges: [
          {CategoryJudge, category: :excellent},
          {CategoryJudge, category: :excellent},
          {CategoryJudge, category: :good}
        ],
        strategy: :majority
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert result == :excellent
      assert metadata.consensus == true
    end

    test "handles judge errors" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          ErrorJudge,
          AlwaysFalseJudge
        ]
      }

      {:error, message} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert message =~ "1 judge(s) failed"
    end

    test "aggregates metadata when enabled" do
      config = %{
        judges: [
          AlwaysTrueJudge,
          AlwaysFalseJudge
        ],
        aggregate_metadata: true
      }

      {:ok, _result, metadata} =
        ExEval.Judge.Composite.Consensus.call("response", "criteria", config)

      assert metadata.individual_results
      assert length(metadata.individual_results) == 2
      assert metadata.reasoning =~ "Always true"
    end
  end

  describe "Weighted judge" do
    test "weighted voting with boolean judges" do
      config = %{
        judges: [
          {AlwaysTrueJudge, 0.6},
          {AlwaysFalseJudge, 0.4}
        ]
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Weighted.call("response", "criteria", config)

      assert result == true
      assert metadata.strategy == :weighted_voting
      assert metadata.true_weight == 0.6
      assert metadata.false_weight == 0.4
    end

    test "weighted average with numeric judges" do
      config = %{
        judges: [
          {{ScoreJudge, score: 0.9}, 0.7},
          {{ScoreJudge, score: 0.6}, 0.3}
        ]
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Weighted.call("response", "criteria", config)

      # Weighted average: (0.9 * 0.7 + 0.6 * 0.3) = 0.63 + 0.18 = 0.81
      assert result == 0.81
      assert metadata.strategy == :weighted_average
      assert metadata.calculation == :weighted_mean
    end

    test "weighted voting with categories" do
      config = %{
        judges: [
          {{CategoryJudge, category: :excellent}, 0.5},
          {{CategoryJudge, category: :good}, 0.3},
          {{CategoryJudge, category: :excellent}, 0.2}
        ]
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Weighted.call("response", "criteria", config)

      assert result == :excellent
      assert metadata.strategy == :weighted_voting
      assert metadata.distribution[:excellent] == 0.7
      assert metadata.distribution[:good] == 0.3
    end

    test "normalizes weights automatically" do
      config = %{
        judges: [
          {AlwaysTrueJudge, 3},
          {AlwaysFalseJudge, 1}
        ]
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Weighted.call("response", "criteria", config)

      assert result == true
      # 3/4
      assert metadata.true_weight == 0.75
      # 1/4
      assert metadata.false_weight == 0.25
    end

    test "handles mixed result types" do
      config = %{
        judges: [
          {{ScoreJudge, score: 0.8}, 0.4},
          {AlwaysTrueJudge, 0.3},
          {{CategoryJudge, category: :good}, 0.3}
        ]
      }

      {:ok, result, metadata} =
        ExEval.Judge.Composite.Weighted.call("response", "criteria", config)

      # Should pick the result from the predominant type (numeric in this case)
      assert is_number(result)
      assert metadata.strategy == :weighted_average
    end
  end

  describe "Integration with ExEval API" do
    alias ExEval.SilentReporter

    test "consensus judge via put_consensus_judge" do
      # Start test-specific supervisor and registry
      start_supervised!({Registry, keys: :unique, name: :test_registry_consensus})

      start_supervised!(
        {DynamicSupervisor, name: :test_supervisor_consensus, strategy: :one_for_one}
      )

      config =
        ExEval.new()
        |> ExEval.put_consensus_judge([
          AlwaysTrueJudge,
          AlwaysTrueJudge,
          AlwaysFalseJudge
        ])
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "test?", category: :test}])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result =
        ExEval.run(config,
          async: false,
          registry: :test_registry_consensus,
          supervisor: :test_supervisor_consensus
        )

      assert result.status == :completed
      assert length(result.results) == 1

      eval_result = hd(result.results)
      assert eval_result.result == true
      assert eval_result.metadata.consensus == true
    end

    test "weighted judge via put_weighted_judge" do
      config =
        ExEval.new()
        |> ExEval.put_weighted_judge([
          {{ScoreJudge, score: 1.0}, 0.8},
          {{ScoreJudge, score: 0.5}, 0.2}
        ])
        |> ExEval.put_dataset([%{input: "test", judge_prompt: "test?", category: :test}])
        |> ExEval.put_response_fn(fn _ -> "response" end)
        |> ExEval.put_reporter(SilentReporter)

      result = ExEval.run(config, async: false)

      assert result.status == :completed
      eval_result = hd(result.results)
      # (1.0 * 0.8 + 0.5 * 0.2)
      assert eval_result.result == 0.9
    end
  end
end
