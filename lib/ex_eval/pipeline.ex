defmodule ExEval.Pipeline do
  @moduledoc """
  Pipeline customization for ExEval evaluations.

  Provides hooks for injecting custom processing logic at different
  stages of the evaluation pipeline:

  - Preprocessors: Transform input before response generation
  - Response processors: Transform responses before judging
  - Postprocessors: Transform judge results after evaluation
  - Middleware: Wrap the entire evaluation process

  ## Examples

      # Add input sanitization
      config = ExEval.new()
      |> ExEval.put_preprocessor(&sanitize_input/1)
      
      # Add response formatting
      config = ExEval.new()
      |> ExEval.put_response_processor(&format_response/1)
      
      # Add result enrichment
      config = ExEval.new()
      |> ExEval.put_postprocessor(&enrich_result/1)
      
      # Add logging middleware
      config = ExEval.new()
      |> ExEval.put_middleware(&logging_middleware/2)
  """

  @typedoc """
  A processor function that takes input and returns transformed output.
  Can also return {:error, reason} to halt processing.
  """
  @type processor :: (any() -> {:ok, any()} | {:error, term()} | any())

  @typedoc """
  Middleware function that wraps evaluation execution.
  Receives the next function to call and evaluation context.
  """
  @type middleware :: (next_fn :: (-> any()), context :: map() -> any())

  @doc """
  Runs a list of preprocessors on input data.

  Preprocessors are run in order, with each processor receiving
  the output of the previous one. If any processor returns an error,
  the chain stops and the error is returned.
  """
  def run_preprocessors(input, []), do: {:ok, input}

  def run_preprocessors(input, [processor | rest]) do
    case apply_processor(processor, input) do
      {:ok, transformed} -> run_preprocessors(transformed, rest)
      {:error, _} = error -> error
      transformed -> run_preprocessors(transformed, rest)
    end
  end

  @doc """
  Runs a list of response processors on response data.
  """
  def run_response_processors(response, []), do: {:ok, response}

  def run_response_processors(response, [processor | rest]) do
    case apply_processor(processor, response) do
      {:ok, transformed} -> run_response_processors(transformed, rest)
      {:error, _} = error -> error
      transformed -> run_response_processors(transformed, rest)
    end
  end

  @doc """
  Runs a list of postprocessors on judge results.
  """
  def run_postprocessors(result, []), do: {:ok, result}

  def run_postprocessors(result, [processor | rest]) do
    case apply_processor(processor, result) do
      {:ok, transformed} -> run_postprocessors(transformed, rest)
      {:error, _} = error -> error
      transformed -> run_postprocessors(transformed, rest)
    end
  end

  @doc """
  Executes a function with middleware wrapping.

  Middleware is applied in reverse order (outermost first),
  creating nested function calls.
  """
  def with_middleware(fun, [], _context), do: fun.()

  def with_middleware(fun, middleware_list, context) do
    middleware_list
    |> Enum.reverse()
    |> Enum.reduce(fun, fn middleware, next_fun ->
      fn -> middleware.(next_fun, context) end
    end)
    |> then(& &1.())
  end

  defp apply_processor(processor, input) when is_function(processor, 1) do
    processor.(input)
  end

  defp apply_processor({module, function}, input) when is_atom(module) and is_atom(function) do
    apply(module, function, [input])
  end

  defp apply_processor({module, function, args}, input)
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, [input | args])
  end

  defp apply_processor(processor, _input) do
    {:error, "Invalid processor: #{inspect(processor)}"}
  end

  defmodule Preprocessors do
    @doc """
    Sanitizes input by removing potential prompt injection attempts.
    """
    def sanitize_input(input) when is_binary(input) do
      input
      |> String.replace(
        ~r/\b(ignore|disregard|forget).*(previous|above|instructions?)\b/i,
        "[SANITIZED]"
      )
      |> String.replace(~r/\b(system|assistant|user):/i, "[SANITIZED]:")
    end

    def sanitize_input(input), do: input

    @doc """
    Truncates input to a maximum length.
    """
    def truncate_input(input, max_length \\ 1000)

    def truncate_input(input, max_length) when is_binary(input) do
      if String.length(input) <= max_length do
        input
      else
        String.slice(input, 0, max_length) <> "..."
      end
    end

    def truncate_input(input, _max_length), do: input

    @doc """
    Normalizes input text (lowercase, trim whitespace).
    """
    def normalize_input(input) when is_binary(input) do
      input
      |> String.trim()
      |> String.downcase()
    end

    def normalize_input(input), do: input
  end

  defmodule ResponseProcessors do
    @doc """
    Removes markdown formatting from responses.
    """
    def strip_markdown(response) when is_binary(response) do
      response
      |> String.replace(~r/```.*?```/s, "")
      |> String.replace(~r/`([^`]+)`/, "\\1")
      |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
      |> String.replace(~r/\*([^*]+)\*/, "\\1")
      |> String.replace(~r/#+\s*/, "")
    end

    def strip_markdown(response), do: response

    @doc """
    Extracts the first sentence from a response.
    """
    def extract_first_sentence(response) when is_binary(response) do
      case String.split(response, ~r/[.!?]+/, parts: 2) do
        [first | _] -> String.trim(first)
        [] -> response
      end
    end

    def extract_first_sentence(response), do: response

    @doc """
    Validates that response meets minimum quality criteria.
    """
    def validate_response(response) when is_binary(response) do
      cond do
        String.length(response) < 3 ->
          {:error, "Response too short"}

        String.match?(response, ~r/^(I don't know|I'm not sure|No|Yes)\.?$/i) ->
          {:error, "Generic response detected"}

        true ->
          {:ok, response}
      end
    end

    def validate_response(response), do: {:ok, response}
  end

  defmodule Postprocessors do
    @doc """
    Adds confidence scoring based on judge metadata.
    """
    def add_confidence_score({:ok, result, metadata}) do
      confidence = calculate_confidence(result, metadata)
      enhanced_metadata = Map.put(metadata, :confidence, confidence)
      {:ok, result, enhanced_metadata}
    end

    def add_confidence_score(result), do: result

    @doc """
    Normalizes boolean results to scores.
    """
    def normalize_to_score({:ok, true, metadata}) do
      {:ok, 1.0, Map.put(metadata, :original_result, true)}
    end

    def normalize_to_score({:ok, false, metadata}) do
      {:ok, 0.0, Map.put(metadata, :original_result, false)}
    end

    def normalize_to_score({:ok, result, metadata}) when is_number(result) do
      {:ok, result, metadata}
    end

    def normalize_to_score(result), do: result

    @doc """
    Filters out results below a quality threshold.
    """
    def quality_filter(result, threshold \\ 0.5)

    def quality_filter({:ok, result, metadata}, threshold) do
      confidence = Map.get(metadata, :confidence, 1.0)

      if confidence >= threshold do
        {:ok, result, metadata}
      else
        {:error, "Result below quality threshold (#{confidence} < #{threshold})"}
      end
    end

    def quality_filter(result, _threshold), do: result

    defp calculate_confidence(result, metadata) do
      base_confidence =
        case result do
          bool when is_boolean(bool) -> 0.8
          score when is_number(score) and score >= 0.8 -> 0.9
          score when is_number(score) and score >= 0.6 -> 0.7
          score when is_number(score) -> 0.5
          _ -> 0.6
        end

      # Adjust based on reasoning length (more reasoning = higher confidence)
      reasoning_bonus =
        case Map.get(metadata, :reasoning) do
          nil ->
            0.0

          reasoning when is_binary(reasoning) ->
            length_bonus = min(String.length(reasoning) / 1000, 0.2)
            length_bonus

          _ ->
            0.0
        end

      min(base_confidence + reasoning_bonus, 1.0)
    end
  end

  defmodule Middleware do
    require Logger

    @doc """
    Logs evaluation timing and results.
    """
    def timing_logger(next_fn, context) do
      start_time = System.monotonic_time(:millisecond)

      result = next_fn.()

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Logger.info("Evaluation completed",
        input: context[:input],
        duration_ms: duration,
        status: get_result_status(result)
      )

      result
    end

    @doc """
    Retries evaluation on failure with exponential backoff.
    """
    def retry_on_failure(next_fn, context) do
      max_retries = Map.get(context, :max_retries, 3)
      base_delay = Map.get(context, :base_delay_ms, 1000)

      retry_with_backoff(next_fn, max_retries, base_delay, 0)
    end

    @doc """
    Caches evaluation results to avoid duplicate work.
    """
    def result_cache(next_fn, context) do
      cache_key = generate_cache_key(context)

      # For now, always execute since no cache is implemented
      result = next_fn.()
      cache_result(cache_key, result)
      result
    end

    defp retry_with_backoff(next_fn, max_retries, base_delay, attempt) do
      try do
        next_fn.()
      rescue
        error ->
          if attempt < max_retries do
            delay = base_delay * :math.pow(2, attempt)

            Logger.warning(
              "Evaluation failed (attempt #{attempt + 1}/#{max_retries + 1}), retrying in #{delay}ms: #{inspect(error)}"
            )

            Process.sleep(round(delay))
            retry_with_backoff(next_fn, max_retries, base_delay, attempt + 1)
          else
            Logger.error("Evaluation failed after #{attempt + 1} attempts: #{inspect(error)}")
            {:error, "Max retries exceeded: #{inspect(error)}"}
          end
      end
    end

    defp get_result_status({:ok, _, _}), do: :success
    defp get_result_status({:error, _}), do: :error
    defp get_result_status(_), do: :unknown

    defp generate_cache_key(context) do
      context
      |> Map.take([:input, :criteria, :judge_config])
      |> :erlang.term_to_binary()
      |> :crypto.hash(:sha256)
      |> Base.encode16(case: :lower)
    end


    defp cache_result(_cache_key, _result) do
      # In a real implementation, this would store in cache
      :ok
    end
  end
end
