defmodule ExEval.DatasetProviderTest do
  use ExUnit.Case
  alias ExEval.DatasetProvider

  describe "capability detection" do
    test "get_capabilities/1 returns correct capabilities for Module provider" do
      capabilities = DatasetProvider.get_capabilities(ExEval.DatasetProvider.Module)

      assert capabilities == %{
               read_only?: true,
               can_create_evaluations?: false,
               can_edit_evaluations?: false,
               can_delete_evaluations?: false,
               can_create_cases?: false,
               can_edit_cases?: false,
               can_delete_cases?: false,
               can_import?: false,
               can_export?: false
             }
    end

    test "get_capabilities/1 returns correct capabilities for TestMock provider" do
      capabilities = DatasetProvider.get_capabilities(ExEval.DatasetProvider.TestMock)

      assert capabilities == %{
               read_only?: true,
               can_create_evaluations?: false,
               can_edit_evaluations?: false,
               can_delete_evaluations?: false,
               can_create_cases?: false,
               can_edit_cases?: false,
               can_delete_cases?: false,
               can_import?: false,
               can_export?: false
             }
    end

    test "supports_editing?/1 returns false for read-only providers" do
      refute DatasetProvider.supports_editing?(ExEval.DatasetProvider.Module)
      refute DatasetProvider.supports_editing?(ExEval.DatasetProvider.TestMock)
    end

    test "supports_evaluation_management?/1 returns false for read-only providers" do
      refute DatasetProvider.supports_evaluation_management?(ExEval.DatasetProvider.Module)
      refute DatasetProvider.supports_evaluation_management?(ExEval.DatasetProvider.TestMock)
    end

    test "supports_import_export?/1 returns false for read-only providers" do
      refute DatasetProvider.supports_import_export?(ExEval.DatasetProvider.Module)
      refute DatasetProvider.supports_import_export?(ExEval.DatasetProvider.TestMock)
    end

    test "read_only?/1 returns true for read-only providers" do
      assert DatasetProvider.read_only?(ExEval.DatasetProvider.Module)
      assert DatasetProvider.read_only?(ExEval.DatasetProvider.TestMock)
    end
  end

  describe "capability detection with full CRUD provider" do
    defmodule FullCRUDProvider do
      @behaviour ExEval.DatasetProvider

      # Required callbacks
      def load(_opts), do: %{cases: [], response_fn: fn _ -> "test" end}
      def list_evaluations(_opts), do: []
      def get_evaluation_info(_id, _opts), do: {:error, :not_found}
      def get_categories(_opts), do: []
      def list_evaluations_by_category(_categories, _opts), do: []

      # Optional callbacks - all implemented
      def create_evaluation(_data), do: {:ok, "eval_1"}
      def update_evaluation(_id, _updates), do: {:ok, %{}}
      def delete_evaluation(_id), do: :ok
      def create_case(_eval_id, _case_data), do: {:ok, "case_1"}
      def update_case(_eval_id, _case_id, _updates), do: {:ok, %{}}
      def delete_case(_eval_id, _case_id), do: :ok
      def import_cases(_eval_id, _cases, _format), do: {:ok, 0}
      def export_cases(_eval_id, _format), do: {:ok, []}
    end

    test "get_capabilities/1 returns all true for full CRUD provider" do
      capabilities = DatasetProvider.get_capabilities(FullCRUDProvider)

      assert capabilities == %{
               # This is always true (all providers support reading)
               read_only?: true,
               can_create_evaluations?: true,
               can_edit_evaluations?: true,
               can_delete_evaluations?: true,
               can_create_cases?: true,
               can_edit_cases?: true,
               can_delete_cases?: true,
               can_import?: true,
               can_export?: true
             }
    end

    test "all capability checks return true for full CRUD provider" do
      assert DatasetProvider.supports_editing?(FullCRUDProvider)
      assert DatasetProvider.supports_evaluation_management?(FullCRUDProvider)
      assert DatasetProvider.supports_import_export?(FullCRUDProvider)
      refute DatasetProvider.read_only?(FullCRUDProvider)
    end
  end

  describe "capability detection with partial provider" do
    defmodule PartialProvider do
      @behaviour ExEval.DatasetProvider

      # Required callbacks
      def load(_opts), do: %{cases: [], response_fn: fn _ -> "test" end}
      def list_evaluations(_opts), do: []
      def get_evaluation_info(_id, _opts), do: {:error, :not_found}
      def get_categories(_opts), do: []
      def list_evaluations_by_category(_categories, _opts), do: []

      # Only case editing - no evaluation management or import/export
      def create_case(_eval_id, _case_data), do: {:ok, "case_1"}
      def update_case(_eval_id, _case_id, _updates), do: {:ok, %{}}
      def delete_case(_eval_id, _case_id), do: :ok
    end

    test "get_capabilities/1 returns mixed capabilities for partial provider" do
      capabilities = DatasetProvider.get_capabilities(PartialProvider)

      assert capabilities == %{
               read_only?: true,
               can_create_evaluations?: false,
               can_edit_evaluations?: false,
               can_delete_evaluations?: false,
               can_create_cases?: true,
               can_edit_cases?: true,
               can_delete_cases?: true,
               can_import?: false,
               can_export?: false
             }
    end

    test "only case editing capabilities return true for partial provider" do
      assert DatasetProvider.supports_editing?(PartialProvider)
      refute DatasetProvider.supports_evaluation_management?(PartialProvider)
      refute DatasetProvider.supports_import_export?(PartialProvider)
      refute DatasetProvider.read_only?(PartialProvider)
    end
  end
end
