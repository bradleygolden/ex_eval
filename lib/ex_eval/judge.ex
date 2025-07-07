defmodule ExEval.Judge do
  @moduledoc """
  Behavior for LLM judges.

  Implement this behavior to add support for new LLM providers used for 
  the LLM-as-judge evaluation pattern.

  Judge providers are responsible for:
  - Building appropriate prompts for their LLM
  - Making the API call 
  - Parsing the response into a standardized format

  ## Example Implementation

      defmodule MyApp.CustomJudge do
        @behaviour ExEval.Judge
        
        @impl true
        def call(response, criteria, config) do
          # Build prompt appropriate for your LLM provider
          prompt = build_custom_prompt(response, criteria)
          
          # Make API call to your LLM provider
          case make_api_call(prompt, config) do
            {:ok, llm_response} ->
              # Parse response into standardized format
              parse_judgment(llm_response)
            {:error, reason} ->
              {:error, reason}
          end
        end
        
        defp parse_judgment(text) do
          # Return {:ok, result, metadata} or {:error, reason}
          # Example for boolean judge:
          passed = String.contains?(text, "YES")
          {:ok, passed, %{reasoning: text}}
          
          # Example for score judge:
          # {:ok, 0.85, %{reasoning: text, confidence: 0.9}}
          
          # Example for multi-dimensional judge:
          # {:ok, %{safety: 0.9, helpfulness: 0.8}, %{reasoning: text}}
        end
      end
  """

  @doc """
  Evaluate a response against criteria using the LLM judge.

  The judge provider is responsible for building an appropriate prompt,
  making the API call, and parsing the response into a standardized format.

  ## Arguments

    * `response` - The AI response text to evaluate
    * `criteria` - The evaluation criteria/prompt for judging
    * `config` - Configuration map containing:
      * `:model` - The model identifier (e.g., "gpt-4.1-mini")
      * `:temperature` - Temperature setting (0.0 to 1.0)
      * Additional provider-specific options

  ## Returns

    * `{:ok, result, metadata}` - Where `result` can be any type (boolean, score, map, etc.) 
      and `metadata` is a map containing additional information about the evaluation
    * `{:error, reason}` - Error tuple with reason

  ## Result Types

  The `result` can be:
  - Boolean: `true`/`false` for pass/fail evaluations
  - Numeric: `0.95` for score-based evaluations  
  - Atom: `:excellent`, `:good`, `:fair`, `:poor` for categorical evaluations
  - Map: `%{safety: 0.9, helpfulness: 0.8}` for multi-dimensional evaluations
  - Any other type specific to your evaluation needs

  The `metadata` map commonly includes:
  - `:reasoning` - Explanation of the judgment
  - `:confidence` - Confidence score
  - `:evaluated_at` - Timestamp
  - Any other judge-specific metadata
  """
  @callback call(response :: String.t(), criteria :: String.t(), config :: map()) ::
              {:ok, result :: any(), metadata :: map()} | {:error, term()}
end
