class AddRemoteWorkspaceDataOperations < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :credential_snapshot, :text
    add_column :workspace_executions, :secret_env_snapshot, :text

    create_table :remote_workspace_operations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :operation_id, null: false
      t.string :kind, null: false
      t.string :spec_hash, null: false
      t.jsonb :spec, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.jsonb :result, null: false, default: {}
      t.text :error_message
      t.timestamps
    end
    add_index :remote_workspace_operations, :operation_id, unique: true
    add_index :remote_workspace_operations, %i[workspace_id state]
  end
end
