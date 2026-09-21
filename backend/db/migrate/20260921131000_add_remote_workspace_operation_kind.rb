class AddRemoteWorkspaceOperationKind < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_workspace_placements, :operation_kind, :string, null: false, default: "prepare"
  end
end
