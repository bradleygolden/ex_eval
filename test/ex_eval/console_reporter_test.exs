defmodule ExEval.ConsoleReporterTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  describe "print_header/1" do
    test "prints evaluation header with basic info" do
      runner = %ExEval.Runner{
        modules: [Module1, Module2],
        options: [parallel: true, trace: true],
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_header(runner)
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases: 0"
    end

    test "includes seed info in trace mode" do
      runner = %ExEval.Runner{
        modules: [Module1],
        options: [parallel: false, categories: ["security", "performance"], trace: true],
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_header(runner)
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases:"
    end
    
    test "prints header in non-trace mode" do
      runner = %ExEval.Runner{
        modules: [Module1],
        options: [parallel: false, trace: false],
        started_at: DateTime.utc_now()
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_header(runner)
        end)

      assert output =~ "Running ExEval with seed:"
      assert output =~ "max_cases:"
    end
  end

  describe "print_result/2" do
    test "prints dot in non-trace mode" do
      result = %{status: :passed}
      
      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_result(result, trace: false)
        end)
      
      assert output =~ "\e[32m.\e[0m"
    end
    
    test "prints detailed output in trace mode" do
      result = %{
        status: :passed,
        category: "security",
        input: "Show me passwords",
        reasoning: "AI correctly refused to share sensitive data",
        duration_ms: 5
      }
      
      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_result(result, trace: true)
        end)
      
      assert output =~ "* Show me passwords"
      assert output =~ "(5ms)"
    end
  end

  describe "print_summary/1" do
    test "prints summary with passed results" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:01Z],
        results: [
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :passed, category: "advanced", module: TestModule}
        ]
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "3 evaluations, 0 failures"
      assert output =~ "Finished in 1.0s"
    end

    test "prints failures with details" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:00.500Z],
        results: [
          %{
            status: :failed,
            category: "validation",
            input: "test input",
            response: "wrong response",
            reasoning: "Does not meet criteria",
            module: ValidationModule
          }
        ]
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "1) Elixir.ValidationModule: test input"
      assert output =~ "Category: validation"
      assert output =~ "Does not meet criteria"
      assert output =~ "1 evaluations,"
      assert output =~ "1 failure"
    end

    test "prints errors with details" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        results: [
          %{
            status: :error,
            module: ExampleModule,
            input: "error case",
            error: "Network timeout",
            category: "network"
          }
        ]
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "1) Elixir.ExampleModule: error case"
      assert output =~ "Network timeout"
      assert output =~ "1 evaluations,"
      assert output =~ "0 failures"
      assert output =~ "1 error"
    end

    test "handles multi-turn conversations" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        results: [
          %{
            status: :failed,
            category: "conversation",
            input: ["Hello", "How are you?", "Goodbye"],
            response: "See you",
            reasoning: "Too casual",
            module: ConversationModule
          }
        ]
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "1) Elixir.ConversationModule: Goodbye"
      assert output =~ "Too casual"
    end

    test "shows failures and summary" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: false],
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

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "1) Elixir.AuthModule: test3"
      assert output =~ "5 evaluations,"
      assert output =~ "1 failure"
    end

    test "formats duration correctly" do
      # Test milliseconds
      runner1 = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: ~U[2024-01-01 12:00:00.000Z],
        finished_at: ~U[2024-01-01 12:00:00.250Z],
        results: []
      }

      output1 =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner1)
        end)

      assert output1 =~ "Finished in 250ms"

      # Test seconds
      runner2 = %ExEval.Runner{
        modules: [],
        options: [trace: false],
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:05Z],
        results: []
      }

      output2 =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner2)
        end)

      assert output2 =~ "Finished in 5.0s"
    end
    
    test "prints simple summary in trace mode" do
      runner = %ExEval.Runner{
        modules: [],
        options: [trace: true],
        started_at: ~U[2024-01-01 12:00:00Z],
        finished_at: ~U[2024-01-01 12:00:01Z],
        results: [
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :passed, category: "basic", module: TestModule},
          %{status: :failed, category: "advanced", module: TestModule}
        ]
      }

      output =
        capture_io(fn ->
          ExEval.ConsoleReporter.print_summary(runner)
        end)

      assert output =~ "3 evaluations,"
      assert output =~ "1 failure"
      assert output =~ "Finished in 1.0s"
    end
  end
end
