class CreateWorkContextBindings < ActiveRecord::Migration[8.1]
  def change
    create_table :work_context_bindings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :work_context, null: false, foreign_key: true, index: false
      t.string :actor_key, null: false
      t.string :conversation_key, null: false
      t.timestamps
    end

    add_index :work_context_bindings, %i[user_id actor_key conversation_key],
              unique: true, name: "index_work_context_bindings_on_conversation"
    add_index :work_context_bindings, %i[user_id actor_key work_context_id],
              unique: true, name: "index_work_context_bindings_on_context"
  end
end
