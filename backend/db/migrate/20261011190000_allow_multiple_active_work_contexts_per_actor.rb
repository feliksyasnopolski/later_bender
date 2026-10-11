class AllowMultipleActiveWorkContextsPerActor < ActiveRecord::Migration[8.0]
  def change
    remove_index :work_contexts, name: "index_work_contexts_on_current_user_and_actor"
    add_index :work_contexts, %i[user_id actor_key ended_at], name: "index_work_contexts_on_actor_and_lifecycle"
  end
end
