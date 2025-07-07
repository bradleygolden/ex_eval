defmodule ExEval.SilentReporter do
  @moduledoc """
  A reporter that produces no output, used for keeping test output clean.
  """
  @behaviour ExEval.Reporter

  @impl true
  def init(_runner, _config), do: {:ok, %{}}

  @impl true
  def report_result(_result, state, _config), do: {:ok, state}

  @impl true
  def finalize(_runner, _state, _config), do: :ok
end
