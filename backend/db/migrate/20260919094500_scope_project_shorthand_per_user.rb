class ScopeProjectShorthandPerUser < ActiveRecord::Migration[8.1]
  def up
    remove_index :projects, name: "index_projects_on_shorthand"
    add_index :projects, %i[user_id shorthand], unique: true
  end

  def down
    remove_index :projects, name: "index_projects_on_user_id_and_shorthand"
    add_index :projects, :shorthand, unique: true
  end
end
