defmodule ExEval.Adapter do
  @moduledoc """
  Behavior for LLM provider adapters.

  Implement this behavior to add support for new LLM providers.

  ## Example Implementation

      defmodule MyApp.CustomAdapter do
        @behaviour ExEval.Adapter
        
        @impl true
        def call(prompt, config) do
          # Make API call to your LLM provider
          # Return {:ok, response_text} or {:error, reason}
        end
      end
  """

  @doc """
  Call the LLM with a prompt and return the response.

  ## Arguments

    * `prompt` - The evaluation prompt to send to the LLM
    * `config` - Configuration map containing:
      * `:model` - The model identifier (e.g., "gpt-4")
      * `:temperature` - Temperature setting (0.0 to 1.0)
      * Additional provider-specific options

  ## Returns

    * `{:ok, response}` - The LLM's text response
    * `{:error, reason}` - Error tuple with reason
  """
  @callback call(prompt :: String.t(), config :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
