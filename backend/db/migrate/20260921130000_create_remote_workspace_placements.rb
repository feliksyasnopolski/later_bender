class CreateRemoteWorkspacePlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_workspace_placements do |t|
      t.references :workspace, null: false, foreign_key: true, index: false
      t.references :remote_agent, null: false, foreign_key: true
      t.string :executor, null: false
      t.string :operation_id, null: false
      t.string :spec_hash, null: false
      t.jsonb :spec, null: false, default: {}
      t.string :provider_workspace_ref
      t.string :state, null: false, default: "pending"
      t.text :error_message
      t.datetime :prepared_at
      t.timestamps
    end
    add_index :remote_workspace_placements, :workspace_id, unique: true
    add_index :remote_workspace_placements, :operation_id, unique: true
    add_index :remote_workspace_placements, %i[remote_agent_id state]
  end
end
