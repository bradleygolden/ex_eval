defmodule ExEval.Application do
  @moduledoc """
  Application module for ExEval.

  Starts the supervision tree for async runners and registries.
  """

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ExEval.RunnerRegistry},
      {DynamicSupervisor, name: ExEval.RunnerSupervisor, strategy: :one_for_one},
      pubsub_child()
    ]

    opts = [strategy: :one_for_one, name: ExEval.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  defp pubsub_child do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      {Phoenix.PubSub, name: ExEval.PubSub}
    else
      nil
    end
  end
end
