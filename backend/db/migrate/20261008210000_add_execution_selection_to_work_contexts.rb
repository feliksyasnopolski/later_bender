class AddExecutionSelectionToWorkContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :work_contexts, :execution_workspace_ref, :string
    add_column :work_contexts, :execution_cwd, :string
    add_column :work_contexts, :foreground_execution_ref, :string
  end
end
