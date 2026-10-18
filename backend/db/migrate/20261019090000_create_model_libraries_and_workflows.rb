class CreateModelLibrariesAndWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :model_workflows do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false
      t.text :workflow, null: false
      t.jsonb :tools, null: false, default: []
      t.string :evidence, null: false, default: "claimed"
      t.jsonb :versions, null: false, default: []
      t.timestamps
    end
    add_index :model_workflows, %i[user_id name], unique: true

    create_table :model_libraries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :source, null: false
      t.text :description
      t.jsonb :exports, null: false, default: []
      t.jsonb :versions, null: false, default: []
      t.timestamps
    end
    add_index :model_libraries, %i[user_id name], unique: true
  end
end
