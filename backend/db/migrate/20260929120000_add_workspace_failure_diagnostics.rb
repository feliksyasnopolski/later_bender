class AddWorkspaceFailureDiagnostics < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_workspace_placements, :error_code, :string
    add_column :remote_workspace_placements, :failure_stage, :string
    add_column :workspace_executions, :error_code, :string
    add_column :workspace_executions, :failure_stage, :string
    add_column :workspace_executions, :error_message, :text
  end
end
