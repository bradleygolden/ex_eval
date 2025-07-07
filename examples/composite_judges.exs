# Composite Judge Examples
#
# This file demonstrates how to use ExEval's composite judge patterns
# for consensus voting, weighted evaluations, and other multi-judge scenarios.

# Example judges for demonstration
defmodule ExampleJudge1 do
  @behaviour ExEval.Judge
  
  @impl true
  def call(response, _criteria, config) do
    model = config[:model] || "default"
    
    # Simulate different judge behavior based on response content
    result = cond do
      String.contains?(response, "excellent") -> true
      String.contains?(response, "good") -> true
      String.contains?(response, "bad") -> false
      true -> String.length(response) > 10
    end
    
    {:ok, result, %{reasoning: "Judge1 (#{model}): #{if result, do: "Good", else: "Poor"} response"}}
  end
end

defmodule ExampleJudge2 do
  @behaviour ExEval.Judge
  
  @impl true
  def call(response, _criteria, config) do
    model = config[:model] || "default"
    
    # Score-based judge (0.0 to 1.0)
    score = response 
            |> String.length() 
            |> Kernel./(100)
            |> min(1.0)
            |> max(0.0)
    
    {:ok, score, %{reasoning: "Judge2 (#{model}): Score #{Float.round(score, 2)} based on length"}}
  end
end

defmodule ExampleJudge3 do
  @behaviour ExEval.Judge
  
  @impl true
  def call(response, _criteria, config) do
    model = config[:model] || "default"
    
    # Categorical judge
    category = cond do
      String.contains?(response, "excellent") -> :excellent
      String.contains?(response, "good") -> :good
      String.contains?(response, "bad") -> :poor
      true -> :fair
    end
    
    {:ok, category, %{reasoning: "Judge3 (#{model}): Categorized as #{category}"}}
  end
end

# Create test dataset
dataset = [
  %{input: "What is AI?", judge_prompt: "Is this a good explanation?", category: :technical},
  %{input: "This is excellent content", judge_prompt: "Rate this content", category: :content},
  %{input: "Bad response", judge_prompt: "Evaluate quality", category: :content},
  %{input: "A good explanation of complex topics", judge_prompt: "Assess clarity", category: :technical}
]

response_fn = fn input ->
  case input do
    "What is AI?" -> "AI is excellent technology that enables machines to learn and make decisions."
    "This is excellent content" -> "This is indeed excellent and comprehensive content that covers all aspects."
    "Bad response" -> "This is bad."
    "A good explanation of complex topics" -> "A good explanation breaks down complex topics into understandable parts."
    _ -> "Default response for #{input}"
  end
end

## Example 1: Consensus Judge - Majority Voting
IO.puts("\n=== Example 1: Majority Consensus ===")

consensus_config = 
  ExEval.new()
  |> ExEval.put_consensus_judge([
    {ExampleJudge1, model: "gpt-4"},
    {ExampleJudge1, model: "claude"},
    {ExampleJudge1, model: "gemini"}
  ])
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_reporter(ExEval.SilentReporter)

result = ExEval.run(consensus_config, async: false)
IO.puts("Consensus results:")
Enum.each(result.results, fn r ->
  IO.puts("  #{r.input} -> #{r.result} (consensus: #{r.metadata.consensus})")
end)

## Example 2: Unanimous Consensus
IO.puts("\n=== Example 2: Unanimous Consensus ===")

unanimous_config = 
  ExEval.new()
  |> ExEval.put_consensus_judge(
    [ExampleJudge1, ExampleJudge1, ExampleJudge1],
    strategy: :unanimous
  )
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_reporter(ExEval.SilentReporter)

result = ExEval.run(unanimous_config, async: false)
IO.puts("Unanimous consensus results:")
Enum.each(result.results, fn r ->
  IO.puts("  #{r.input} -> #{r.result} (consensus: #{r.metadata.consensus})")
end)

## Example 3: Weighted Voting
IO.puts("\n=== Example 3: Weighted Voting ===")

weighted_config = 
  ExEval.new()
  |> ExEval.put_weighted_judge([
    {{ExampleJudge2, model: "gpt-4"}, 0.5},      # High weight for score judge
    {{ExampleJudge1, model: "claude"}, 0.3},     # Medium weight for boolean judge
    {{ExampleJudge3, model: "gemini"}, 0.2}      # Low weight for category judge
  ])
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_reporter(ExEval.SilentReporter)

result = ExEval.run(weighted_config, async: false)
IO.puts("Weighted voting results:")
Enum.each(result.results, fn r ->
  IO.puts("  #{r.input} -> #{inspect(r.result)} (strategy: #{r.metadata.strategy})")
end)

## Example 4: Threshold Consensus (75% agreement required)
IO.puts("\n=== Example 4: Threshold Consensus (75%) ===")

threshold_config = 
  ExEval.new()
  |> ExEval.put_consensus_judge(
    [ExampleJudge1, ExampleJudge1, ExampleJudge1, ExampleJudge1],
    strategy: :threshold,
    threshold: 0.75,
    aggregate_metadata: true
  )
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_reporter(ExEval.SilentReporter)

result = ExEval.run(threshold_config, async: false)

if result.status == :completed do
  IO.puts("75% Threshold consensus results:")
  Enum.each(result.results, fn r ->
    IO.puts("  #{r.input} -> #{r.result}")
    IO.puts("    Agreement: #{Float.round(r.metadata.agreement_ratio * 100, 1)}%")
    IO.puts("    Consensus: #{r.metadata.consensus}")
  end)
else
  IO.puts("Threshold consensus evaluation failed: #{result.error}")
end

## Example 5: Mixed Judge Types with Consensus
IO.puts("\n=== Example 5: Mixed Judge Types ===")

mixed_config = 
  ExEval.new()
  |> ExEval.put_consensus_judge([
    ExampleJudge2,  # Score judge
    ExampleJudge2,  # Score judge
    ExampleJudge3   # Category judge
  ])
  |> ExEval.put_dataset(dataset)
  |> ExEval.put_response_fn(response_fn)
  |> ExEval.put_reporter(ExEval.SilentReporter)

result = ExEval.run(mixed_config, async: false)

if result.status == :completed do
  IO.puts("Mixed judge type results:")
  Enum.each(result.results, fn r ->
    IO.puts("  #{r.input} -> #{inspect(r.result)}")
    IO.puts("    Distribution: #{inspect(r.metadata[:distribution])}")
  end)
else
  IO.puts("Mixed judge evaluation failed: #{result.error}")
end

## Example 6: Show Detailed Metrics
IO.puts("\n=== Example 6: Detailed Metrics ===")

detailed_result = ExEval.run(consensus_config, async: false)

if detailed_result.status == :completed do
  IO.puts("Metrics for consensus evaluation:")
  IO.inspect(detailed_result.metrics, pretty: true)
else
  IO.puts("Failed to get metrics: #{detailed_result.error}")
end

IO.puts("\n=== Composite Judge Examples Complete ===")
IO.puts("These examples show how to combine multiple judges using:")
IO.puts("- Majority consensus (> 50% agreement)")
IO.puts("- Unanimous consensus (100% agreement)")  
IO.puts("- Threshold consensus (custom % agreement)")
IO.puts("- Weighted voting (different judge weights)")
IO.puts("- Mixed judge types (boolean, score, categorical)")