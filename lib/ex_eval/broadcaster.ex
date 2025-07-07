defmodule ExEval.Broadcaster do
  @moduledoc """
  Behavior for broadcasting evaluation events.

  Allows external packages to implement real-time broadcasting
  without coupling ExEval core to any specific PubSub system.

  ## Example Implementation

      defmodule MyApp.EvalBroadcaster do
        @behaviour ExEval.Broadcaster
        
        @impl true
        def init(config) do
          {:ok, %{topic: config[:topic]}}
        end
        
        @impl true
        def broadcast(:started, data, state) do
          MyApp.PubSub.broadcast(state.topic, {:eval_started, data})
          :ok
        end
        
        @impl true
        def broadcast(event, data, state) do
          MyApp.PubSub.broadcast(state.topic, {event, data})
          :ok
        end
      end

  ## Events

  The following events are broadcast during evaluation:

  - `:started` - When evaluation begins
  - `:progress` - Periodic progress updates
  - `:result` - Individual evaluation results (optional)
  - `:completed` - When evaluation completes successfully
  - `:failed` - When evaluation fails
  """

  @type event :: :started | :progress | :result | :completed | :failed | atom()
  @type event_data :: map()
  @type state :: any()

  @doc """
  Initialize the broadcaster with configuration.

  Called once when the evaluation runner starts.

  ## Parameters

  - `config` - Configuration map passed from ExEval configuration

  ## Returns

  - `{:ok, state}` - Success with broadcaster state
  - `{:error, reason}` - Initialization failed
  """
  @callback init(config :: map()) :: {:ok, state} | {:error, term()}

  @doc """
  Broadcast an evaluation event.

  ## Parameters

  - `event` - The event type
  - `data` - Event data including timestamps, progress, results, etc.
  - `state` - The broadcaster state from init/1

  ## Returns

  - `:ok` - Event was broadcast (or failed silently)

  ## Event Data

  Common fields in event data:

  - `:run_id` - The ExEval runner ID
  - `:external_id` - External ID if provided
  - `:timestamp` - UTC timestamp of the event

  Event-specific fields:

  ### :started
  - `:started_at` - When evaluation started
  - `:total_cases` - Total number of evaluation cases

  ### :progress  
  - `:completed` - Number of completed evaluations
  - `:total` - Total number of evaluations
  - `:percentage` - Progress percentage (0.0 - 100.0)
  - `:current_dataset_index` - Current dataset being processed

  ### :result
  - `:index` - Result index
  - `:input` - The input that was evaluated
  - `:result` - The evaluation result
  - `:status` - Result status (:evaluated, :passed, :failed, :error)

  ### :completed
  - `:finished_at` - When evaluation finished
  - `:duration_ms` - Total duration in milliseconds
  - `:metrics` - Final evaluation metrics
  - `:results_summary` - Summary of results

  ### :failed
  - `:error` - Error description
  - `:finished_at` - When evaluation failed
  """
  @callback broadcast(event :: event(), data :: event_data(), state :: state()) :: :ok

  @doc """
  Clean up broadcaster resources.

  Called when the evaluation runner terminates.

  ## Parameters

  - `reason` - Termination reason
  - `state` - The broadcaster state

  ## Returns

  - `:ok`
  """
  @callback terminate(reason :: any(), state :: state()) :: :ok

  @optional_callbacks terminate: 2
end
