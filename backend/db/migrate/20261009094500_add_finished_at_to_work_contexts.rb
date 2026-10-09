class AddFinishedAtToWorkContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :work_contexts, :finished_at, :datetime
    add_index :work_contexts, %i[user_id finished_at]
  end
end
