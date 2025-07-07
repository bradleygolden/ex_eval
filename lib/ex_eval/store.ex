defmodule ExEval.Store do
  @moduledoc """
  Behavior for persisting evaluation run results.

  Store implementations handle saving and querying evaluation runs,
  enabling experiment tracking and historical analysis.

  ## Example Implementation

      defmodule MyApp.PostgresStore do
        @behaviour ExEval.Store

        @impl true
        def save_run(run_data) do
          # Save to PostgreSQL
          :ok
        end

        @impl true
        def get_run(run_id) do
          # Query from PostgreSQL
          %{id: run_id, ...}
        end

        @impl true
        def list_runs(opts \\ []) do
          # Query with filters
          [...]
        end

        @impl true
        def query(criteria) do
          # Complex queries
          [...]
        end
      end

  ## Usage

      config = 
        ExEval.new()
        |> ExEval.put_store(MyApp.PostgresStore)
        |> ExEval.put_experiment(:my_experiment)
  """

  @doc """
  Saves a completed evaluation run.

  Receives the full run state including:
  - id: Unique run identifier
  - status: :completed, :error, etc.
  - results: List of individual evaluation results
  - metadata: Experiment name, parameters, tags
  - started_at/finished_at: Timestamps
  - metrics: Computed metrics (if available)
  """
  @callback save_run(run_data :: map()) :: :ok | {:error, term()}

  @doc """
  Retrieves a run by ID.

  Returns the full run data or nil if not found.
  """
  @callback get_run(run_id :: String.t()) :: map() | nil

  @doc """
  Lists runs, optionally filtered.

  ## Options
  - `:experiment` - Filter by experiment name
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list_runs(opts :: keyword()) :: [map()]

  @doc """
  Queries runs by various criteria.

  Supports complex filtering, ordering, and aggregation.

  ## Examples

      # Filter by experiment and metrics
      query(%{
        experiment: :safety_v2,
        metrics: [pass_rate: [:>, 0.95]]
      })

      # Order by metrics
      query(%{
        order_by: {:metrics, :pass_rate, :desc},
        limit: 10
      })

      # Filter by tags
      query(%{
        tags: %{environment: :production}
      })
  """
  @callback query(criteria :: map()) :: [map()]
end
