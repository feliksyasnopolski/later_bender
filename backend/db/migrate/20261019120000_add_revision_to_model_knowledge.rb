class AddRevisionToModelKnowledge < ActiveRecord::Migration[8.1]
  def change
    add_column :model_libraries, :revision, :integer, null: false, default: 1
    add_column :model_workflows, :revision, :integer, null: false, default: 1
  end
end
