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

  Returns a map with :provider and :config keys for the LLM judge.
  """
  def judge_config(dataset)
end

# Implementation for module-based datasets (backward compatibility)
defimpl ExEval.Dataset, for: Atom do
  def cases(module) do
    dataset = ExEval.DatasetProvider.Module.load(module: module)
    dataset.cases
  end

  def response_fn(module) do
    dataset = ExEval.DatasetProvider.Module.load(module: module)
    dataset.response_fn
  end

  def metadata(module) do
    dataset = ExEval.DatasetProvider.Module.load(module: module)
    Map.get(dataset, :metadata, %{module: module})
  end

  def setup_fn(module) do
    dataset = ExEval.DatasetProvider.Module.load(module: module)
    Map.get(dataset, :setup_fn)
  end

  def judge_config(module) do
    dataset = ExEval.DatasetProvider.Module.load(module: module)

    %{
      provider: Map.get(dataset, :judge_provider, ExEval.JudgeProvider.LangChain),
      config: Map.get(dataset, :config, %{})
    }
  end
end

# Implementation for map-based datasets (for Ecto/database)
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
    %{
      provider: Map.get(map, :judge_provider, ExEval.JudgeProvider.LangChain),
      config: Map.get(map, :config, %{})
    }
  end
end
