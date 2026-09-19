class UseIntegerWorkspacePublicRefs < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :public_number, :integer
    add_index :workspaces, %i[user_id public_number], unique: true
    remove_index :workspaces, :ref
    add_index :workspaces, %i[user_id ref], unique: true

    Workspace.reset_column_information
    Workspace.order(:user_id, :id).group_by(&:user_id).each_value do |workspaces|
      workspaces.each_with_index do |workspace, index|
        old_ref = workspace.ref
        Workspace.where(id: workspace.id).update_all(public_number: index + 1, legacy_ref: workspace.legacy_ref.presence || old_ref, ref: "WS-#{index + 1}")
      end
    end
  end

  def down
    Workspace.reset_column_information
    Workspace.where.not(legacy_ref: nil).find_each { |workspace| workspace.update_columns(ref: workspace.legacy_ref) }
    remove_index :workspaces, %i[user_id public_number]
    remove_index :workspaces, %i[user_id ref]
    add_index :workspaces, :ref, unique: true
    remove_column :workspaces, :public_number
  end
end
