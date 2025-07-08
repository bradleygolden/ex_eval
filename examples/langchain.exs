Mix.install([
  {:ex_eval, path: "./", override: true},
  {:ex_eval_langchain, path: "../ex_eval_langchain"}
])

# TEMP: Force loading of the ExEval.Langchain module
# This is needed when using Mix.install with path dependencies due to lazy loading
# Remove this line when packages are published to Hex
Code.ensure_loaded(ExEval.Langchain)

dataset = [
  %{
    input: "What is the capital of France?",
    judge_prompt: "The answer should be Paris",
    category: :geography
  }
]

response_fn = fn
  "What is the capital of France?" ->
    "Paris"

  _ ->
    "I don't know"
end

ExEval.new()
|> ExEval.put_judge(ExEval.Langchain, model: "gpt-4.1-mini")
|> ExEval.put_dataset(dataset)
|> ExEval.put_response_fn(response_fn)
|> ExEval.put_experiment(:langchain)
|> ExEval.run(async: false)
