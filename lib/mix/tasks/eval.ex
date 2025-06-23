defmodule Mix.Tasks.Ai.Eval do
  @moduledoc """
  Run AI evaluations using ExEval framework.

  ## Usage

      mix ai.eval                    # Run all evaluations
      mix ai.eval path/to/eval.exs   # Run specific evaluation file
      mix ai.eval --category security # Run only security evaluations

  ## Options

    * `--category` - Filter by category (can be used multiple times)
    * `--sequential` - Run evaluations sequentially instead of in parallel
    * `--max-concurrency` - Maximum concurrent evaluations (default: 5)
    * `--trace` - Show detailed output for each evaluation
  """

  use Mix.Task

  @shortdoc "Run AI evaluations"

  @impl true
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          category: :keep,
          sequential: :boolean,
          max_concurrency: :integer,
          trace: :boolean
        ]
      )

    Mix.Task.run("app.start")

    eval_files =
      case files do
        [] -> Path.wildcard("evals/**/*_eval.exs")
        files -> files
      end

    if Enum.empty?(eval_files) do
      Mix.shell().info("No evaluation files found")
      System.halt(0)
    end

    modules =
      Enum.flat_map(eval_files, fn file ->
        compiled = Code.compile_file(file)

        Enum.flat_map(compiled, fn {module, _} ->
          if function_exported?(module, :__ex_eval_eval_cases__, 0) do
            [module]
          else
            []
          end
        end)
      end)

    if Enum.empty?(modules) do
      Mix.shell().info("No ExEval evaluation modules found")
      System.halt(0)
    end

    runner_opts = [
      parallel: !opts[:sequential],
      categories: Keyword.get_values(opts, :category),
      trace: opts[:trace] || false
    ]

    runner_opts =
      if max_conc = opts[:max_concurrency] do
        Keyword.put(runner_opts, :max_concurrency, max_conc)
      else
        runner_opts
      end

    runner = ExEval.Runner.run(modules, runner_opts)

    exit_code =
      case Enum.group_by(runner.results, & &1.status) do
        %{failed: _failed} -> 1
        %{error: _errors} -> 1
        _ -> 0
      end

    System.at_exit(fn _ -> exit({:shutdown, exit_code}) end)
  end
end
