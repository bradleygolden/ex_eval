defprotocol ExEval.Dataset do
  @moduledoc """
  Protocol for interacting with evaluation datasets.

  This protocol provides a uniform interface for accessing dataset information
  regardless of the source (modules, Ecto schemas, Ash resources, etc.).
  """

  @doc """
  Get evaluation cases from the dataset.

  Returns a list of evaluation cases, each containing input and judge_prompt.
  """
  def cases(dataset)

  @doc """
  Get the response function for generating AI responses.

  Returns a function that takes input and returns a response string.
  """
  def response_fn(dataset)

  @doc """
  Get dataset metadata.

  Returns a map containing information about the dataset like name, module, etc.
  """
  def metadata(dataset)

  @doc """
  Get setup function if any.

  Returns a function that provides context for evaluations, or nil if none.
  """
  def setup_fn(dataset)

  @doc """
  Get judge configuration.

  Returns a map with :judge and :config keys for the LLM judge.
  """
  def judge_config(dataset)
end

# Implementation for map-based datasets (inline configuration)
defimpl ExEval.Dataset, for: Map do
  def cases(%{cases: cases}), do: cases
  def cases(_), do: []

  def response_fn(%{response_fn: func}) when is_function(func), do: func
  def response_fn(_), do: fn _input -> "No response function defined" end

  def metadata(%{metadata: meta}), do: meta
  def metadata(map), do: map

  def setup_fn(%{setup_fn: func}) when is_function(func), do: func
  def setup_fn(_), do: nil

  def judge_config(map) do
    # Return the dataset's judge configuration if specified
    # The runner will merge this with the ExEval config
    %{
      judge: Map.get(map, :judge),
      config: Map.get(map, :config, %{})
    }
  end
end
