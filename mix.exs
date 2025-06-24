defmodule ExEval.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_eval,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        test: :test,
        "ai.eval": :eval
      ],

      name: "ExEval",
      description:
        "Dataset-oriented evaluation framework for AI/LLM applications using LLM-as-judge pattern"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:langchain, "~> 0.3.0", optional: true},

      {:jason, "~> 1.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:eval), do: ["lib", "evals/support"]
  defp elixirc_paths(_), do: ["lib"]
end
