defmodule ExEval.Application do
  @moduledoc """
  Supervisor for ExEval's async evaluation infrastructure.

  Starts and manages the registry and dynamic supervisor needed for
  running evaluations asynchronously.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ExEval.RunnerRegistry},
      {DynamicSupervisor, name: ExEval.RunnerSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
