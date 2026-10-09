class ScopeWorkContextsToAuthenticatedActor < ActiveRecord::Migration[8.1]
  def change
    remove_index :work_contexts, name: "index_work_contexts_on_current_user"
    add_column :work_contexts, :actor_key, :string
    add_index :work_contexts, %i[user_id actor_key], unique: true,
              where: "ended_at IS NULL AND actor_key IS NOT NULL",
              name: "index_work_contexts_on_current_user_and_actor"
  end
end
