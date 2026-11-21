class AddRemoteStartAcceptedAtToWorkspaceExecutions < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_executions, :remote_start_accepted_at, :datetime
    add_column :workspace_executions, :remote_next_poll_at, :datetime
  end
end
