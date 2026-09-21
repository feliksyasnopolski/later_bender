class AddRemoteExecutionState < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_executions, :remote_operation_id, :string
    add_column :workspace_executions, :spec_hash, :string
    add_column :workspace_executions, :remote_spec, :jsonb, null: false, default: {}
    add_column :workspace_executions, :cancel_operation_id, :string
    add_column :workspace_executions, :stdout_data, :binary
    add_column :workspace_executions, :stderr_data, :binary
    add_index :workspace_executions, :remote_operation_id, unique: true
    add_index :workspace_executions, :cancel_operation_id, unique: true
  end
end
