defmodule ExEval.JudgeProvider do
  @moduledoc """
  Behavior for LLM judge providers.

  Implement this behavior to add support for new LLM providers used for 
  the LLM-as-judge evaluation pattern.

  ## Example Implementation

      defmodule MyApp.CustomJudgeProvider do
        @behaviour ExEval.JudgeProvider
        
        @impl true
        def call(prompt, config) do
          # Make API call to your LLM provider for judgment
          # Return {:ok, response_text} or {:error, reason}
        end
      end
  """

  @doc """
  Call the LLM with a judgment prompt and return the response.

  ## Arguments

    * `prompt` - The evaluation prompt to send to the LLM for judgment
    * `config` - Configuration map containing:
      * `:model` - The model identifier (e.g., "gpt-4.1-mini")
      * `:temperature` - Temperature setting (0.0 to 1.0)
      * Additional provider-specific options

  ## Returns

    * `{:ok, response}` - The LLM's judgment response text
    * `{:error, reason}` - Error tuple with reason
  """
  @callback call(prompt :: String.t(), config :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
