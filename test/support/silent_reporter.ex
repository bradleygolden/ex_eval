defmodule ExEval.Reporter.Silent do
  @moduledoc """
  A silent reporter for tests that doesn't output anything.
  """

  @behaviour ExEval.Reporter

  @impl true
  def init(_runner, _config) do
    {:ok, %{}}
  end

  @impl true
  def report_result(_result, state, _config) do
    {:ok, state}
  end

  @impl true
  def finalize(_runner, _state, _config) do
    :ok
  end
end
