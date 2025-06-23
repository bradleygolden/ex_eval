defmodule ExEval.Adapters.LangChain do
  @moduledoc """
  LangChain adapter for ExEval.

  Uses LangChain to communicate with LLM providers. LangChain will
  automatically detect API keys from environment variables:
  - OPENAI_API_KEY for OpenAI models
  - ANTHROPIC_API_KEY for Anthropic models
  - etc.

  ## Configuration Options

  - `:chat_model` - The LangChain chat model module to use (default: `LangChain.ChatModels.ChatOpenAI`)
  - `:model` - The specific model to use (default: "gpt-4.1-mini")
  - `:temperature` - Temperature for responses (default: 0.1)
  - `:api_key` - Optional API key override

  ## Examples

      # Use OpenAI (default)
      ExEval.new(adapter: ExEval.Adapters.LangChain)
      
      # Use Anthropic
      ExEval.new(
        adapter: ExEval.Adapters.LangChain,
        config: %{
          chat_model: LangChain.ChatModels.ChatAnthropic,
          model: "claude-3-haiku-20240307"
        }
      )

  Supports both text responses and structured JSON responses.
  """

  @behaviour ExEval.Adapter

  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  @impl true
  def call(prompt, config) do
    model = build_model(config)

    result =
      %{llm: model}
      |> LLMChain.new!()
      |> LLMChain.add_message(Message.new_user!(prompt))
      |> LLMChain.run()

    case result do
      {:ok, chain} ->
        {:ok, get_response_content(chain)}

      {:error, %{message: message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp build_model(config) do
    chat_model_module = config[:chat_model] || LangChain.ChatModels.ChatOpenAI

    base_config = %{
      model: config[:model] || "gpt-4.1-mini",
      temperature: config[:temperature] || 0.1
    }

    base_config =
      if config[:api_key] do
        Map.put(base_config, :api_key, config[:api_key])
      else
        base_config
      end

    model_config =
      if config[:structured_response] do
        Map.merge(base_config, %{
          json_response: true,
          json_schema: get_json_schema(config)
        })
      else
        base_config
      end

    chat_model_module.new!(model_config)
  end

  defp get_json_schema(config) do
    config[:json_schema] ||
      %{
        "name" => "evaluation_result",
        "schema" => %{
          "type" => "object",
          "properties" => %{
            "judgment" => %{
              "type" => "string",
              "enum" => ["YES", "NO"],
              "description" => "Whether the response meets the criteria"
            },
            "reasoning" => %{
              "type" => "string",
              "description" => "Brief explanation of the judgment"
            },
            "confidence" => %{
              "type" => "number",
              "minimum" => 0,
              "maximum" => 1,
              "description" => "Confidence level of the judgment"
            }
          },
          "required" => ["judgment"],
          "additionalProperties" => false
        }
      }
  end

  defp get_response_content(chain) do
    case chain do
      %{last_message: %{content: content}} when is_map(content) ->
        Jason.encode!(content)

      %{last_message: %{content: content}} when is_binary(content) ->
        content

      _ ->
        raise "Unexpected chain structure"
    end
  end
end
