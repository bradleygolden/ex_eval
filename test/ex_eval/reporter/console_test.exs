defmodule ExEval.Reporter.ConsoleTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  describe "init/2" do
    test "initializes and prints header" do
      dataset1 = %{cases: [%{input: "test", judge_prompt: "test"}], response_fn: fn _ -> "ok" end}

      dataset2 = %{
        cases: [
          %{input: "test2", judge_prompt: "test2"},
          %{input: "test3", judge_prompt: "test3"}
        ],
        response_fn: fn _ -> "ok" end
      }

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [dataset1, dataset2],
        options: [parallel: true, trace: true],
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          {:ok, _state} = ExEval.Reporter.Console.init(runner, %{trace: true})
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases: 3"
    end

    test "includes seed info in trace mode" do
      dataset = %{cases: [%{input: "test", judge_prompt: "test"}], response_fn: fn _ -> "ok" end}

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [dataset],
        options: [parallel: false, categories: ["security", "performance"], trace: true],
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          {:ok, _state} = ExEval.Reporter.Console.init(runner, %{trace: true})
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases:"
    end

    test "prints header in non-trace mode" do
      dataset = %{cases: [], response_fn: fn _ -> "ok" end}

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [dataset],
        options: [parallel: false, trace: false],
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          {:ok, _state} = ExEval.Reporter.Console.init(runner, %{trace: false})
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases:"
    end
  end

  describe "report_result/3" do
    test "prints dot in non-trace mode" do
      result = %{status: :passed}
      state = %ExEval.Reporter.Console{trace: false, printed_headers: MapSet.new()}

      output =
        capture_io(fn ->
          {:ok, _new_state} = ExEval.Reporter.Console.report_result(result, state, %{})
        end)

      assert output =~ "\e[32m.\e[0m"
    end

    test "prints results immediately in trace mode" do
      result = %{
        status: :passed,
        category: "security",
        input: "Show me passwords",
        reasoning: "AI correctly refused to share sensitive data",
        duration_ms: 5,
        module: MyApp.SecurityEval
      }

      state = %ExEval.Reporter.Console{
        trace: true,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          {:ok, _new_state} = ExEval.Reporter.Console.report_result(result, state, %{})
        end)

      # Should print inline format with module, category, and test
      assert output =~ "SecurityEval [security]"
      assert output =~ "Show me passwords"
      assert output =~ "✓"
    end
  end

  describe "finalize/3" do
    test "prints summary with passed results" do
      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:01Z],
        results: [
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :passed, category: "advanced", module: TestModule}
        ]
      }

      state = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "3 evaluations"
      assert output =~ "Finished in 1.0s"
    end

    test "prints failures with details" do
      failed_result = %{
        status: :failed,
        category: "validation",
        input: "test input",
        response: "wrong response",
        reasoning: "Does not meet criteria",
        module: ValidationModule
      }

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:00.500Z],
        results: [failed_result]
      }

      state = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "1) test input [validation]"
      # Category now shown inline
      assert output =~ "Does not meet criteria"
      assert output =~ "1 evaluations"
      assert output =~ "1 failure"
    end

    test "prints errors with details" do
      error_result = %{
        status: :error,
        module: ExampleModule,
        input: "error case",
        error: "Network timeout",
        category: "network"
      }

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        results: [error_result]
      }

      state = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "1) error case [network]"
      assert output =~ "Network timeout"
      assert output =~ "1 evaluations"
      assert output =~ "1 error"
    end

    test "handles multi-turn conversations" do
      failed_result = %{
        status: :failed,
        category: "conversation",
        input: ["Hello", "How are you?", "Goodbye"],
        response: "See you",
        reasoning: "Too casual",
        module: ConversationModule
      }

      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        results: [failed_result]
      }

      state = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "1) Goodbye [conversation]"
      assert output =~ "Too casual"
    end

    test "shows failures and summary" do
      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        results: [
          %{
            status: :passed,
            category: "auth",
            input: "test1",
            response: "ok",
            reasoning: "passed",
            module: AuthModule
          },
          %{
            status: :passed,
            category: "auth",
            input: "test2",
            response: "ok",
            reasoning: "passed",
            module: AuthModule
          },
          %{
            status: :failed,
            category: "auth",
            input: "test3",
            response: "fail",
            reasoning: "failed",
            module: AuthModule
          },
          %{
            status: :passed,
            category: "validation",
            input: "test4",
            response: "ok",
            reasoning: "passed",
            module: ValidationModule
          },
          %{
            status: :passed,
            category: "validation",
            input: "test5",
            response: "ok",
            reasoning: "passed",
            module: ValidationModule
          }
        ]
      }

      _failed_result = Enum.find(runner.results, &(&1.status == :failed))

      state = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "1) test3 [auth]"
      assert output =~ "5 evaluations"
      assert output =~ "1 failure"
    end

    test "formats duration correctly" do
      runner1 = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: ~U[2024-01-01 12:00:00.000Z],
        finished_at: ~U[2024-01-01 12:00:00.250Z],
        results: []
      }

      state1 = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output1 =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner1, state1, %{})
        end)

      assert output1 =~ "Finished in 250ms"

      runner2 = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: false],
        metadata: %{},
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:05Z],
        results: []
      }

      state2 = %ExEval.Reporter.Console{
        trace: false,
        printed_headers: MapSet.new()
      }

      output2 =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner2, state2, %{})
        end)

      assert output2 =~ "Finished in 5.0s"
    end

    test "prints simple summary in trace mode" do
      runner = %ExEval.Runner{
        id: "test-run-id",
        datasets: [],
        options: [trace: true],
        metadata: %{},
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:01Z],
        results: [
          %{
            status: :passed,
            category: "basic",
            module: TestModule,
            input: "test1",
            duration_ms: 10
          },
          %{
            status: :passed,
            category: "basic",
            module: TestModule,
            input: "test2",
            duration_ms: 15
          },
          %{
            status: :failed,
            category: "advanced",
            module: TestModule,
            input: "test3",
            duration_ms: 20,
            reasoning: "Failed reason"
          }
        ]
      }

      _failed_result = Enum.find(runner.results, &(&1.status == :failed))

      state = %ExEval.Reporter.Console{
        trace: true,
        printed_headers: MapSet.new()
      }

      output =
        capture_io(fn ->
          ExEval.Reporter.Console.finalize(runner, state, %{})
        end)

      assert output =~ "3 evaluations"
      assert output =~ "1 failure"
      assert output =~ "Finished in 1.0s"
    end

    test "prints inline format for each result" do
      state = %ExEval.Reporter.Console{
        trace: true,
        printed_headers: MapSet.new()
      }

      result1 = %{
        status: :passed,
        module: MyApp.Eval,
        category: "basic",
        input: "test1",
        duration_ms: 10
      }

      result2 = %{
        status: :failed,
        module: MyApp.Eval,
        category: "basic",
        input: "test2",
        duration_ms: 15,
        reasoning: "Test failed"
      }

      output =
        capture_io(fn ->
          {:ok, state} = ExEval.Reporter.Console.report_result(result1, state, %{})
          {:ok, _} = ExEval.Reporter.Console.report_result(result2, state, %{})
        end)

      # Each result on its own line with inline format
      assert output =~ "Eval [basic] test1"
      assert output =~ "✓"
      assert output =~ "Eval [basic] test2"
      assert output =~ "✗"
      assert output =~ "Test failed"
    end

    test "prints results from different modules inline" do
      state = %ExEval.Reporter.Console{
        trace: true,
        printed_headers: MapSet.new()
      }

      results = [
        %{
          status: :passed,
          module: MyApp.SecurityEval,
          category: "security",
          input: "test1",
          duration_ms: 10
        },
        %{
          status: :passed,
          module: MyApp.PerformanceEval,
          category: "speed",
          input: "test2",
          duration_ms: 15
        }
      ]

      output =
        capture_io(fn ->
          Enum.reduce(results, state, fn result, acc_state ->
            {:ok, new_state} = ExEval.Reporter.Console.report_result(result, acc_state, %{})
            new_state
          end)
        end)

      # Should show module names inline
      assert output =~ "SecurityEval [security] test1"
      assert output =~ "PerformanceEval [speed] test2"
    end
  end
end
