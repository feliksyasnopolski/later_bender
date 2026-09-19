class ReconcileWorkspacePublicRefs < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :legacy_ref, :string
    add_index :workspaces, :legacy_ref
    Workspace.reset_column_information
    Workspace.find_each do |workspace|
      next unless workspace.ref.start_with?("WSR-")

      workspace.update_columns(legacy_ref: workspace.ref, ref: "WS-#{SecureRandom.hex(12)}")
    end
  end

  def down
    Workspace.reset_column_information
    Workspace.where.not(legacy_ref: nil).find_each { |workspace| workspace.update_columns(ref: workspace.legacy_ref) }
    remove_index :workspaces, :legacy_ref
    remove_column :workspaces, :legacy_ref
  end
end
