defmodule ExEval.ReporterTest do
  use ExUnit.Case
  alias ExEval.Reporter

  describe "available_reporters/0" do
    test "includes Console reporter" do
      reporters = Reporter.available_reporters()
      assert ExEval.Reporter.Console in reporters
    end

    test "returns a list" do
      reporters = Reporter.available_reporters()
      assert is_list(reporters)
      assert length(reporters) >= 1
    end
  end

  describe "reporter_info/1" do
    test "returns info for Console reporter" do
      info = Reporter.reporter_info(ExEval.Reporter.Console)

      assert info.name == "Console"
      assert info.description =~ "console"
      assert info.required_deps == []
      assert info.required_config == []
      assert :trace in info.optional_config
    end

    test "returns generic info for unknown reporter" do
      defmodule CustomReporter do
        @behaviour ExEval.Reporter
        def init(_runner, _config), do: {:ok, %{}}
        def report_result(_result, state, _config), do: {:ok, state}
        def finalize(_runner, _state, _config), do: :ok
      end

      info = Reporter.reporter_info(CustomReporter)

      assert info.name == "ExEval.ReporterTest.CustomReporter"
      assert info.description == "Custom reporter"
      assert info.required_deps == :unknown
      assert info.required_config == :unknown
    end
  end
end
