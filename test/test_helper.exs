ExUnit.start()

# Start Phoenix.PubSub for tests if available
if Code.ensure_loaded?(Phoenix.PubSub) do
  children = [
    {Phoenix.PubSub, name: TestPubSub}
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
end
