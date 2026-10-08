class CreateWorkContexts < ActiveRecord::Migration[8.1]
  def change
    create_table :work_contexts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :task, foreign_key: { on_delete: :nullify }
      t.text :scratchpad, null: false, default: ""
      t.datetime :ended_at
      t.timestamps
    end
    add_index :work_contexts, %i[user_id ended_at]
    add_index :work_contexts, :user_id, unique: true, where: "ended_at IS NULL", name: "index_work_contexts_on_current_user"
  end
end
