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

      # Basic info
      name: "ExEval",
      description:
        "Dataset-oriented evaluation framework for AI/LLM applications using LLM-as-judge pattern"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # LangChain for LLM interactions (optional - only if using default adapter)
      {:langchain, "~> 0.3.0", optional: true},

      # JSON parsing
      {:jason, "~> 1.4"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:eval), do: ["lib", "evals/support"]
  defp elixirc_paths(_), do: ["lib"]
end
